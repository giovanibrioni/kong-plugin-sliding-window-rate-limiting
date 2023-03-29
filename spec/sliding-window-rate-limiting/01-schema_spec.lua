local PLUGIN_NAME = "sliding-window-rate-limiting"
local schema_def = require("kong.plugins." .. PLUGIN_NAME .. ".schema")

local v = require("spec.helpers").validate_plugin_config_schema

describe(PLUGIN_NAME .. ": (schema)", function()
  describe("should fail when", function()
    it("limit is missing", function()
      local config = {window_size = 60}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("required field missing",err.config.limit)
    end)

    it("window_size is missing", function()
      local config = {limit = 10}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("required field missing",err.config.window_size)

    end)

    it("window_size and limit are missing", function()
      local config = {}
      local ok, err = v(config, schema_def)
      local result = {}
      result['limit'] = 'required field missing'
      result['window_size'] = 'required field missing'

      assert.falsy(ok)
      assert.same(result, err.config)
    end)

    it("window_size is less then 0", function()
      local config = { window_size = 0 , limit = 10}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("value must be greater than 0", err.config.window_size)
    end)

    it("limit is less then 0", function()
      local config = { window_size = 60 , limit = -5}
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equals("value must be greater than 0", err.config.limit)
    end)


    it("is limited by header but the header_name field is missing", function()
      local config = { window_size = 60 , limit = 10, limit_by = "header", header_name = nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.header_name)
    end)

    it("is limited by path but the path field is missing", function()
      local config = { window_size = 60 , limit = 10, limit_by = "path", path =  nil }
      local ok, err = v(config, schema_def)
      assert.falsy(ok)
      assert.equal("required field missing", err.config.path)
    end)
  end)

  describe("should work when", function()
    it("proper config validates min", function()
      local config = { window_size = 60 , limit = 10 }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (header)", function()
      local config = { window_size = 60 , limit = 10, limit_by = "header", header_name = "X-App-Version" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)

    it("proper config validates (path)", function()
      local config = { window_size = 60 , limit = 10, limit_by = "path", path = "/request" }
      local ok, _, err = v(config, schema_def)
      assert.truthy(ok)
      assert.is_nil(err)
    end)
  end)

end)
