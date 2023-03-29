local helpers        = require "spec.helpers"
local cjson          = require "cjson"

local REDIS_HOST     = "myredis"
local REDIS_PORT     = 6379
local REDIS_PASSWORD = ""
local REDIS_DATABASE = 1

local fmt = string.format

local PLUGIN_NAME = "sliding-window-rate-limiting"


local function GET(url, opts, res_status)
  ngx.sleep(0.010)

  local client = helpers.proxy_client()
  local res, err  = client:get(url, opts)
  if not res then
    client:close()
    return nil, err
  end

  local body, err = assert.res_status(res_status, res)
  if not body then
    return nil, err
  end

  client:close()

  return res, body
end

local function flush_redis()
  local redis = require "resty.redis"
  local red = redis:new()
  red:set_timeout(2000)
  local ok, err = red:connect(REDIS_HOST, REDIS_PORT)
  if not ok then
    error("failed to connect to Redis: " .. err)
  end

  if REDIS_PASSWORD and REDIS_PASSWORD ~= "" then
    local ok, err = red:auth(REDIS_PASSWORD)
    if not ok then
      error("failed to connect to Redis: " .. err)
    end
  end

  local ok, err = red:select(REDIS_DATABASE)
  if not ok then
    error("failed to change Redis database: " .. err)
  end

  red:flushall()
  red:close()
end

for _, strategy in ipairs({ "postgres", "off" }) do
  for _, policy in ipairs({ "redis" }) do
    describe(fmt("Plugin: sliding-window-rate-limiting (access) with policy: %s [#%s]", policy, strategy), function()
      local bp
      local db
      local client

      lazy_setup(function()
        helpers.kill_all()
        flush_redis()

        bp, db = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

        local route1 = bp.routes:insert {
          hosts = { "test1.com" },
        }

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = route1.id },
          config = {
            policy         = policy,
            window_size    = 10,
            limit          = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            hide_client_headers  = false,
          }
        })

        local route_grpc_1 = assert(bp.routes:insert {
          protocols = { "grpc" },
          paths = { "/hello.HelloService/" },
          service = assert(bp.services:insert {
            name = "grpc",
            url = "grpc://localhost:15002",
          }),
        })

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = route_grpc_1.id },
          config = {
            policy         = policy,
            window_size    = 10,
            limit          = 6,
            fault_tolerant = false,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            hide_client_headers  = false,
          }
        })

        local route2 = bp.routes:insert {
          hosts      = { "test2.com" },
        }

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = route2.id },
          config = {
            limit          = 6,
            window_size    = 10,
            fault_tolerant = false,
            policy         = policy,
            limit_by       = "header",
            header_name    = "X-Client-Id",
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
            hide_client_headers  = false,
          }
        })

        local route3 = bp.routes:insert {
          hosts = { "test3.com" },
        }

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = route3.id },
          config = {
            hide_client_headers = true,
            policy         = policy,
            window_size    = 10,
            limit          = 6,
            redis_host     = REDIS_HOST,
            redis_port     = REDIS_PORT,
            redis_password = REDIS_PASSWORD,
            redis_database = REDIS_DATABASE,
          },
        })

        local service4 = bp.services:insert()

        local route4 = bp.routes:insert {
          hosts      = { "failtest4.com" },
          protocols  = { "http", "https" },
          service    = service4
        }

        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route4.id },
          config  = { limit = 6, window_size = 1, policy = policy, redis_host = "5.5.5.5", fault_tolerant = false },
        }

        local service5 = bp.services:insert()

        local route5 = bp.routes:insert {
          hosts      = { "failtest5.com" },
          protocols  = { "http", "https" },
          service    = service5
        }

        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route5.id },
          config = { limit = 6, window_size = 1, policy = policy, redis_host = "5.5.5.5", fault_tolerant = true },
        }

        local route6 = bp.routes:insert {
          hosts      = { "test6.com" },
        }

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = route6.id },
          config = {
            limit                = 6,
            window_size          = 10,
            fault_tolerant       = false,
            policy               = policy,
            limit_by             = "header",
            header_name          = "X-Client-Id",
            redis_host           = REDIS_HOST,
            redis_port           = REDIS_PORT,
            redis_password       = REDIS_PASSWORD,
            redis_database       = REDIS_DATABASE,
            fallback_enabled     = true,
            fallback_by          = "header",
            fallback_header_name = "X-Client-IP",
            fallback_limit       = 11,
            fallback_window_size = 10,
            hide_client_headers  = false,
          }
        })

        -- start kong
        assert(helpers.start_kong({
          -- set the strategy
          database   = strategy,
          -- use the custom test template to create a local mock server
          nginx_conf = "spec/fixtures/custom_nginx.template",
          -- make sure our plugin gets loaded
          plugins = "bundled," .. PLUGIN_NAME,
        }))
      end)

      lazy_teardown(function()
        helpers.stop_kong()
        assert(db:truncate())
      end)

      before_each(function()
        client = helpers.proxy_client()
      end)

      after_each(function()
        if client then client:close() end
      end)

      describe("IP address: ", function()
        it("Allow 6 requests, then RateLimit, then wait and allow 6 requests again.", function()

          local first_request_time = ngx.now()

          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test1.com"
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

          -- Additonal request, while limit is 6/minute
          local res = client:get("/status/200", {
            headers = {
              host = "test1.com"
            }
          })
          assert.response(res).has.status(429)
          assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
          local body = assert.response(res).has.jsonbody()
          assert.equal("API rate limit exceeded", body['message'])

          local time_to_sleep_until_ok = (11 + first_request_time) - ngx.now()
          ngx.sleep(time_to_sleep_until_ok)

          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test1.com"
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

        end)
      end)

      describe("Via header: ", function()
        it("Allow 6 requests, then RateLimit, then allow 6 requests to another X-Client-Id, then wait and allow 6 requests again.", function()

          local first_request_time = ngx.now()

          -- Allow 6 requests
          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test2.com",
                ["X-Client-Id"] = "e672d6cd-d768-412b-92d3-5ae3c8b434c7",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

          -- Then RateLimit Additonal request, while limit is 6/minute
          local res = client:get("/status/200", {
            headers = {
              host = "test2.com",
              ["X-Client-Id"] = "e672d6cd-d768-412b-92d3-5ae3c8b434c7",
            }
          })
          assert.response(res).has.status(429)
          assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
          local body = assert.response(res).has.jsonbody()
          assert.equal("API rate limit exceeded", body['message'])

          -- Then allow 6 requests to another X-Client-Id
          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test2.com",
                ["X-Client-Id"] = "another",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

          --Then wait
          local time_to_sleep_until_ok = (11 + first_request_time) - ngx.now()
          ngx.sleep(time_to_sleep_until_ok)

          --Then allow 6 requests again
          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test2.com",
                ["X-Client-Id"] = "e672d6cd-d768-412b-92d3-5ae3c8b434c7",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

        end)
      end)

      describe("Config with hide_client_headers", function()
        it("does not send rate-limit headers when hide_client_headers==true", function()
          local res = client:get("/status/200", {
            headers = { Host = "test3.com" },
          }, 200)
          assert.is_nil(res.headers["slidingwindow-ratelimit-limit"])
          assert.is_nil(res.headers["slidingwindow-ratelimit-remaining"])
          assert.is_nil(res.headers["slidingwindow-ratelimit-reset"])
        end)
      end)

      describe("Fault tolerancy", function()

        it("does not work if an error occurs", function()
          local _, body = GET("/status/200", {
            headers = { Host = "failtest4.com" },
          }, 500)

          local json = cjson.decode(body)
          assert.same({ message = "An unexpected error occurred" }, json)
        end)

        it("keeps working if an error occurs", function()
          local res = GET("/status/200", {
            headers = { Host = "failtest5.com" },
          }, 200)

          assert.falsy(res.headers["slidingwindow-ratelimit-limit"])
          assert.falsy(res.headers["slidingwindow-ratelimit-remaining"])
          assert.falsy(res.headers["slidingwindow-ratelimit-reset"])
        end)
      end)

      describe("Via header WITH Fallback: ", function()
        it("Allow 11 requests using X-Client-IP then RateLimit, then allow 6 requests to X-Client-Id, then wait and allow 11 requests again using X-Client-IP.", function()

          local first_request_time = ngx.now()

          -- Allow 6 requests
          for i = 1, 11 do
            local res = client:get("/status/200", {
              headers = {
                host = "test6.com",
                ["X-Client-IP"] = "200.100.100.200",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(11, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(11 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

          -- Then RateLimit Additonal request, while limit is 6/minute
          local res = client:get("/status/200", {
            headers = {
              host = "test6.com",
              ["X-Client-IP"] = "200.100.100.200",
            }
          })
          assert.response(res).has.status(429)
          assert.are.same(11, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
          assert.are.same(0, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
          local body = assert.response(res).has.jsonbody()
          assert.equal("API rate limit exceeded", body['message'])

          -- Then allow 6 requests to another X-Client-Id
          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test6.com",
                ["X-Client-Id"] = "e672d6cd-d768-412b-92d3-5ae3c8b434c7",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(6, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(6 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

          --Then wait
          local time_to_sleep_until_ok = (11 + first_request_time) - ngx.now()
          ngx.sleep(time_to_sleep_until_ok)

          --Then allow 6 requests again
          for i = 1, 6 do
            local res = client:get("/status/200", {
              headers = {
                host = "test6.com",
                ["X-Client-IP"] = "200.100.100.200",
              }
            })
            assert.response(res).has.status(200)
            assert.are.same(11, tonumber(res.headers["slidingwindow-ratelimit-limit"]))
            assert.are.same(11 - i, tonumber(res.headers["slidingwindow-ratelimit-remaining"]))
            local reset = tonumber(res.headers["slidingwindow-ratelimit-reset"])
            assert.equal(true, reset <= 10 and reset >= 0)
          end

        end)
      end)


    end)
  end
end
