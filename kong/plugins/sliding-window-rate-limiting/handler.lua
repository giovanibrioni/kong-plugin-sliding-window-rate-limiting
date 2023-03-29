-- Copyright (C) Kong Inc.
local plugin_name = ({ ... })[1]:match("^kong%.plugins%.([^%.]+)")

local policies = require("kong.plugins." .. plugin_name .. ".policies")

local kong = kong
local max = math.max
local error = error
local tostring = tostring

local EMPTY = {}

local RATELIMIT_LIMIT     = "SlidingWindow-RateLimit-Limit"
local RATELIMIT_REMAINING = "SlidingWindow-RateLimit-Remaining"
local RATELIMIT_RESET     = "SlidingWindow-RateLimit-Reset"

local RateLimitingHandler = {}


RateLimitingHandler.PRIORITY = 901
RateLimitingHandler.VERSION = "0.1.0"


local function get_identifier(conf)
  local identifier

  if conf.limit_by == "service" then
    identifier = (kong.router.get_service() or
                  EMPTY).id
  elseif conf.limit_by == "consumer" then
    identifier = (kong.client.get_consumer() or
                  kong.client.get_credential() or
                  EMPTY).id

  elseif conf.limit_by == "credential" then
    identifier = (kong.client.get_credential() or
                  EMPTY).id

  elseif conf.limit_by == "header" then
    identifier = kong.request.get_header(conf.header_name)

  elseif conf.limit_by == "path" then
    local req_path = kong.request.get_path()
    if req_path == conf.path then
      identifier = req_path
    end
  end

  if not identifier then
    if conf.fallback_enabled then
      if conf.fallback_by == "header" then
        identifier = kong.request.get_header(conf.fallback_header_name)
        if not identifier then
          return kong.client.get_forwarded_ip(), true
        end
        return identifier, true
      end
    end
    return kong.client.get_forwarded_ip(), false
  end
  return identifier, false
end


local function get_usage(conf, identifier, window_size)
  local current_usage, reset, err = policies[conf.policy].usage(conf, identifier, window_size)
  if err then
    return nil, nil, err
  end

  return current_usage, reset
end

local function get_headers(conf, limit, usage, remaining_time)
  local headers

  if not conf.hide_client_headers then
    headers = {}

    headers[RATELIMIT_LIMIT] = limit
    headers[RATELIMIT_REMAINING] = max(0, limit - usage)
    headers[RATELIMIT_RESET] = remaining_time
  end

  return headers

end

function RateLimitingHandler:access(conf)
  -- Consumer is identified by ip address or authenticated_credential id
  local identifier, fallback = get_identifier(conf)
  local fault_tolerant = conf.fault_tolerant

  local limit = fallback and conf.fallback_limit or conf.limit
  local window_size = fallback and conf.fallback_window_size or conf.window_size

  local current_usage, remaining_time, err = get_usage(conf, identifier, window_size)
  if err then

    if not fault_tolerant then
      return error(err)
    end
    kong.log.err("failed to call get_usage(): ", tostring(err))

  elseif current_usage and remaining_time then
    local headers = get_headers(conf, limit, current_usage, remaining_time)

    if current_usage > limit then
      -- If limit is exceeded, terminate the request
      return kong.response.error(429, "API rate limit exceeded", headers)
    end

    if headers then
      kong.response.set_headers(headers)
    end

  else
    kong.log.err("failed to get current_usage: ", tostring(err))
  end
end

return RateLimitingHandler
