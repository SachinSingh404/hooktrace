# frozen_string_literal: true

require "cgi"
require "erb"
require "json"
require "rack"

module Hooktrace
  class Web
    VIEWS_DIR = File.expand_path("web/views", __dir__).freeze
    ASSETS_DIR = File.expand_path("web/assets", __dir__).freeze

    def self.call(env)
      new.call(env)
    end

    def call(env)
      req = Rack::Request.new(env)
      path = req.path_info.to_s
      path = "/" if path.empty?

      route_request(req, path)
    end

    private

    def route_request(req, path)
      case [req.request_method, path]
      when ["GET", "/"], ["GET", "/events"]
        render_events(req)
      when ["GET", "/contracts"]
        render_contracts(req)
      when ["POST", "/events/clear"]
        Hooktrace.store.clear!
        redirect_to(req, "/events")
      else
        [404, html_headers, ["<h1>404 Not Found</h1>"]]
      end
    end

    def render_events(req)
      status_filter = req.params["status"]
      events = Hooktrace.store.all(limit: 100, status: status_filter)
      stats = Hooktrace.store.stats
      contracts_count = Hooktrace.registry.size

      body = render_view(
        "events",
        events: events,
        stats: stats,
        contracts_count: contracts_count,
        status_filter: status_filter,
        base_path: req.script_name.to_s
      )
      render_layout("Webhook Events", body, req, active_tab: "events")
    end

    def render_contracts(req)
      contracts = Hooktrace.registry.values.sort_by(&:name)
      body = render_view("contracts", contracts: contracts, base_path: req.script_name.to_s)
      render_layout("Contracts", body, req, active_tab: "contracts")
    end

    def render_layout(title, content, req, active_tab:)
      css = File.read(File.join(ASSETS_DIR, "application.css"))
      html = render_template(
        "layout",
        title: title,
        content: content,
        stylesheet: css,
        active_tab: active_tab,
        base_path: req.script_name.to_s
      )
      [200, html_headers, [html]]
    end

    def render_view(name, **locals)
      render_template(name, **locals)
    end

    def render_template(name, **locals)
      path = File.join(VIEWS_DIR, "\#{name}.erb")
      erb = ERB.new(File.read(path, encoding: "UTF-8"))
      context = TemplateContext.new(locals)
      erb.result(context.get_binding)
    end

    def html_headers
      { "content-type" => "text/html; charset=utf-8" }
    end

    def redirect_to(req, path)
      base = req.script_name.to_s
      target = base.empty? ? path : File.join(base, path)
      [302, { "location" => target }, []]
    end

    class TemplateContext
      def initialize(vars)
        vars.each { |k, v| instance_variable_set("@\#{k}", v) }
      end

      def get_binding
        binding
      end

      def h(str)
        CGI.escapeHTML(str.to_s)
      end
    end
  end
end
