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

      return forbidden_response(req) if req.post? && !origin_allowed?(req)

      route_request(req, path)
    rescue StandardError => e
      handle_server_error(e)
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
      when ["POST", "/events/revalidate_failed"]
        Hooktrace.revalidate_failed
        redirect_to(req, "/events")
      else
        handle_dynamic_route(req, path)
      end
    end

    def handle_dynamic_route(req, path)
      if req.post? && path.match?(%r{\A/events/[^/]+/revalidate\z})
        event_id = path.sub(%r{\A/events/([^/]+)/revalidate\z}, '\1')
        revalidate_event(req, event_id)
      elsif req.get? && path.start_with?("/events/")
        render_event_detail(req, path.sub("/events/", ""))
      else
        [404, html_headers, ["<h1>404 Not Found</h1>"]]
      end
    end

    def revalidate_event(req, event_id)
      outcome = Hooktrace.revalidate(event_id)
      return json_revalidation_response(req, event_id, outcome) if wants_json?(req)

      redirect_to(req, safe_return_path(req.params["return_to"]) || "/events/#{event_id}")
    rescue Hooktrace::EventNotFoundError => e
      if wants_json?(req)
        return [404, json_headers, [JSON.generate(status: "not_found", event_id: event_id, message: e.message)]]
      end

      [404, html_headers, ["<h1>Event Not Found</h1>"]]
    end

    def json_revalidation_response(req, event_id, outcome)
      endpoint = "#{req.script_name}/events/#{event_id}/revalidate"
      message = if outcome.valid?
                  "Event '#{event_id}' re-validated successfully against current contracts."
                else
                  "Event '#{event_id}' re-validated with #{outcome.errors.size} contract violation(s)."
                end
      payload = outcome.to_h.merge(api: "POST #{endpoint}", message: message, stats: Hooktrace.store.stats)
      [200, json_headers, [JSON.generate(payload)]]
    end

    def wants_json?(req)
      req.env["HTTP_ACCEPT"].to_s.include?("application/json")
    end

    def safe_return_path(path)
      return nil if path.nil? || path.empty?
      return path if path.start_with?("/events") && !path.start_with?("//")

      nil
    end

    def render_events(req)
      status_filter = req.params["status"]
      type_filter = req.params["type"]
      events = Hooktrace.store.all(limit: 100, event_type: type_filter, status: status_filter)
      stats = Hooktrace.store.stats

      render_page(
        req,
        title: "Events",
        template: :events,
        locals: {
          events: events,
          stats: stats,
          contracts_count: Hooktrace.registry.size,
          status_filter: status_filter,
          base_path: req.script_name.to_s
        }
      )
    end

    def render_contracts(req)
      render_page(
        req,
        title: "Contracts",
        template: :contracts,
        locals: { contracts: Hooktrace.registry.values }
      )
    end

    def render_event_detail(req, event_id)
      event = Hooktrace.store.find(event_id)
      return [404, html_headers, ["<h1>Event Not Found</h1>"]] unless event

      render_page(
        req,
        title: "Event #{event.id}",
        template: :event_detail,
        locals: { event: event, base_path: req.script_name.to_s }
      )
    end

    def render_page(req, title:, template:, locals: {})
      content = render_erb(template, locals)
      active_tab = title.downcase.include?("contract") ? "contracts" : "events"

      html = render_erb(
        :layout,
        title: title,
        active_tab: active_tab,
        base_path: req.script_name.to_s,
        stylesheet: stylesheet,
        content: content
      )
      [200, html_headers, [html]]
    end

    def render_erb(name, locals = {})
      template_path = File.join(VIEWS_DIR, "#{name}.erb")
      erb = ERB.new(File.read(template_path, encoding: "UTF-8"), trim_mode: "-")
      ctx = WebTemplateContext.new(locals)
      erb.result(ctx.template_binding)
    end

    def stylesheet
      @stylesheet ||= File.read(File.join(ASSETS_DIR, "application.css"), encoding: "UTF-8")
    end

    def origin_allowed?(req)
      origin = req.env["HTTP_ORIGIN"] || req.env["HTTP_REFERER"]
      return true if origin.nil? || origin.empty?

      begin
        parsed = URI.parse(origin)
      rescue URI::InvalidURIError
        return true
      end
      return true unless parsed&.host

      parsed.host == req.host
    end

    def forbidden_response(req)
      msg = "Cross-origin request blocked"
      return [403, json_headers, [JSON.generate(error: msg)]] if wants_json?(req)

      [403, html_headers, ["<h1>403 Forbidden</h1><p>#{h(msg)}</p>"]]
    end

    def handle_server_error(err)
      env_mode = ENV["RACK_ENV"] || ENV["RAILS_ENV"] || "development"
      body = if %w[development test].include?(env_mode)
               "<h1>Hooktrace::Web Error</h1><pre>#{h(err.full_message)}</pre>"
             else
               "<h1>500 Internal Server Error</h1><p>An unexpected error occurred in Hooktrace::Web.</p>"
             end
      [500, html_headers, [body]]
    end

    def redirect_to(req, path)
      [302, { "location" => "#{req.script_name}#{path}" }, []]
    end

    def html_headers
      { "content-type" => "text/html; charset=utf-8" }
    end

    def json_headers
      { "content-type" => "application/json; charset=utf-8" }
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end
  end

  class WebTemplateContext
    def initialize(locals)
      locals.each do |key, value|
        define_singleton_method(key) { value }
      end
    end

    def h(value)
      CGI.escapeHTML(value.to_s)
    end

    def template_binding
      binding
    end
  end
end
