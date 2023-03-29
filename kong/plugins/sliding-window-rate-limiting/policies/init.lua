local reports = require "kong.reports"
local redis = require "resty.redis"


local kong = kong
local null = ngx.null
local fmt = string.format
local os_getenv = os.getenv
local kong_name = os_getenv("KONG_NAME") or "kong"


local EMPTY_UUID = "00000000-0000-0000-0000-000000000000"


local function is_present(str)
  return str and str ~= "" and str ~= null
end


local function get_service_and_route_ids(conf)
  conf = conf or {}

  local service_id = conf.service_id
  local route_id   = conf.route_id

  if not service_id or service_id == null then
    service_id = EMPTY_UUID
  end

  if not route_id or route_id == null then
    route_id = EMPTY_UUID
  end

  return service_id, route_id
end


local get_local_key = function(conf, identifier, window_size)

  local service_id, route_id = get_service_and_route_ids(conf)

  return fmt("slidingwindow_ratelimiting:%s:%s:%s:%s:%s", kong_name, route_id, service_id, identifier, window_size)
end


local sock_opts = {}

local function get_redis_connection(conf)
  local red = redis:new()
  red:set_timeout(conf.redis_timeout)
  -- use a special pool name only if redis_database is set to non-zero
  -- otherwise use the default pool name host:port
  sock_opts.pool = conf.redis_database and
                    conf.redis_host .. ":" .. conf.redis_port ..
                    ":" .. conf.redis_database
  local ok, err = red:connect(conf.redis_host, conf.redis_port,
                              sock_opts)
  if not ok then
    kong.log.err("failed to connect to Redis: ", err)
    return nil, err
  end

  local times, err = red:get_reused_times()
  if err then
    kong.log.err("failed to get connect reused times: ", err)
    return nil, err
  end

  if times == 0 then
    if is_present(conf.redis_password) then
      local ok, err = red:auth(conf.redis_password)
      if not ok then
        kong.log.err("failed to auth Redis: ", err)
        return nil, err
      end
    end

    if conf.redis_database ~= 0 then
      -- Only call select first time, since we know the connection is shared
      -- between instances that use the same redis database

      local ok, err = red:select(conf.redis_database)
      if not ok then
        kong.log.err("failed to change Redis database: ", err)
        return nil, err
      end
    end
  end

  return red
end

local function consume_limit_redis(conf, cache_key, window_size)
  local red, err = get_redis_connection(conf)
  if not red then
    return nil, nil, err
  end

  reports.retrieve_redis_version(red)

  local result, err = red:eval([[
    local cache_key, expiration = KEYS[1], ARGV[1]
    local result_incr = redis.call("incr", cache_key)
    if result_incr == 1 then
      redis.call("expire", cache_key, expiration)
    end
    local remaining_time = redis.call("ttl", cache_key)

    return {result_incr, remaining_time}
  ]], 1, cache_key, window_size)

  if not result or not result[1] or not result[2] then
    kong.log.err("failed to run eval command in Redis: ", err)
    return nil, nil, err
  end

  local ok, err = red:set_keepalive(10000, 100)
  if not ok then
    kong.log.err("failed to set Redis keepalive: ", err)
    return nil, nil, err
  end

  local current_usage = result[1]
  local remaining_time = result[2]

  return current_usage, remaining_time
end

return {
  ["redis"] = {
    usage = function(conf, identifier, window_size)

      local cache_key = get_local_key(conf, identifier, window_size)

      local current_usage, remaining_time, err = consume_limit_redis(conf, cache_key, window_size)

      if err then
        return nil, nil, err
      end

      return current_usage, remaining_time
    end
  }
}
