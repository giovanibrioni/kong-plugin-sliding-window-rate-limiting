local typedefs    = require "kong.db.schema.typedefs"
local plugin_name = ({ ... })[1]:match("^kong%.plugins%.([^%.]+)")

local policy = {
    type = "string",
    default = "redis",
    len_min = 0,
    one_of = {
      "redis",
    },
  }

return {
  name = plugin_name,
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
        type = "record",
        fields = {
          { window_size = { type = "number", required = true, gt = 0 }, },
          { limit = { type = "number", required = true, gt = 0 }, },
          { limit_by = {
              type = "string",
              default = "consumer",
              one_of = { "consumer", "credential", "ip", "service", "header", "path" },
          }, },
          { header_name = typedefs.header_name },
          { path = typedefs.path },
          { policy = policy },
          { fault_tolerant = { type = "boolean", required = true, default = true }, },
          { redis_host = typedefs.host({ default = 'localhost' }) },
          { redis_port = typedefs.port({ default = 6379 }), },
          { redis_password = { type = "string", len_min = 0 }, },
          { redis_timeout = { type = "number", default = 2000, }, },
          { redis_database = { type = "integer", default = 0 }, },
          { hide_client_headers = { type = "boolean", required = true, default = true }, },
          { fallback_enabled = { type = "boolean", required = true, default = false }, },
          { fallback_by = {
            type = "string",
            default = "header",
            one_of = { "header" },
            required = false,
          }, },
          { fallback_header_name = typedefs.header_name({required = false, default = "x-client-ip"}) },
          { fallback_window_size = { type = "number", required = false, gt = 0 }, },
          { fallback_limit = { type = "number", required = false, gt = 0 }, },
        },
      },
    },
  },
  entity_checks = {
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_host", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_port", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "header" },
      then_field = "config.header_name", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.limit_by", if_match = { eq = "path" },
      then_field = "config.path", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.policy", if_match = { eq = "redis" },
      then_field = "config.redis_timeout", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.fallback_enabled", if_match = { eq = true },
      then_field = "config.fallback_by", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.fallback_enabled", if_match = { eq = true },
      then_field = "config.fallback_header_name", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.fallback_enabled", if_match = { eq = true },
      then_field = "config.fallback_window_size", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.fallback_enabled", if_match = { eq = true },
      then_field = "config.fallback_limit", then_match = { required = true },
    } },
    { conditional = {
      if_field = "config.fallback_by", if_match = { eq = "header" },
      then_field = "config.fallback_header_name", then_match = { required = true },
    } },
  },
}
