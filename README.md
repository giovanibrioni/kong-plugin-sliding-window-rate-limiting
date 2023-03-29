# Kong Plugin Sliding Window Rate-Limiting

summary: This plugin has the same purpose as the [rate-limiting plugin](https://github.com/Kong/kong/tree/master/kong/plugins/), although but this implementation has better accuracy.

Kong rate-limiting plugin has a race condition problem in addition it works with the fixed window algorithm which is less accurate than the sliding window algorithm, which is the algorithm used here

**NOTE**: window_size is ALWAYS in **seconds**

Fallback rate-limiting can be useful when the regular rules can not be applyed, e.g: Rate-Limiting by header, but the header does not exists in the request (and it would use the requester IP).
By configuring the Fallback Rate-Limiting it is possible the configure rules like: "Apply _X RPS_ to 'X-Client-Id' or, if 'X-Client-Id' do not exist: _Y RPS_ to 'X-Client-IP'".

## Configuration

Add environment variable `KONG_NAME` to cache_key. This enables two or more Kongs to share the same Redis.
If not specified, the default value is `kong`.

How to use:

- Define `KONG_NAME` as an environment variable on the host or container you want to use with the unique name of that Kong.
- Create or update file kong-main-include.conf and add `env KONG_NAME;` to it. This gives nginx access to the environment variable.
- Define `KONG_NGINX_MAIN_INCLUDE` as an environment variable pointing to the file kong-main-include.conf. As alternative, you can add `nginx_main_include=<path>/kong-main-include.conf` to the `kong.conf` file.

### Fallback rule

Imagine the scenario that you configured rate-limiting based on header `x-client-id` but this header is not present. The default behavior would apply the same limit/window_size to the requester IP: it would throttle more than it should!!

Thinking about this scenario, now it is possible to have "fallback" values for "limit" and "window_size" to be used as a "fallback rate-limiting by header".

Configuration example:

- An authenticated user has 10 requests per 60 seconds. Requests without "X-Client-Id" has 200 in 60 seconds.

```yaml
  plugins:
    - name: sliding-window-rate-limiting
      config:
        hide_client_headers: false
        fault_tolerant: true
        limit_by: header
        header_name: X-Client-Id
        limit: 10
        window_size: 60
        policy: redis
        redis_host: redis-server
        redis_port: 6379
        fallback_enabled: true
        fallback_by: header
        fallback_header_name: "x-client-ip"
        fallback_limit: 200
        fallback_window_size: 60
```

<!-- BEGINNING OF KONG-PLUGIN DOCS HOOK -->
## Plugin Priority

Priority: **901**

## Plugin Version

Version: **0.1.0**

## Config

| name | type | required | validations | default |
|-----|-----|-----|-----|-----|
| window_size | number | <pre>true</pre> | <pre>- gt: 0</pre> |  |
| limit | number | <pre>true</pre> | <pre>- gt: 0</pre> |  |
| limit_by | string | <pre>false</pre> | <pre>- one_of:<br/>  - consumer<br/>  - credential<br/>  - ip<br/>  - service<br/>  - header<br/>  - path</pre> | <pre>consumer</pre> |
| header_name | string | <pre>false</pre> |  |  |
| path | string | <pre>false</pre> | <pre>- match_none:<br/>  - err: must not have empty segments<br/>    pattern: //<br/>- starts_with: /</pre> |  |
| policy | string | <pre>false</pre> | <pre>- len_min: 0<br/>- one_of:<br/>  - redis</pre> | <pre>redis</pre> |
| fault_tolerant | boolean | <pre>true</pre> |  | <pre>true</pre> |
| redis_host | string | <pre>false</pre> |  | <pre>localhost</pre> |
| redis_port | integer | <pre>false</pre> | <pre>- between:<br/>  - 0<br/>  - 65535</pre> | <pre>6379</pre> |
| redis_password | string | <pre>false</pre> | <pre>- len_min: 0</pre> |  |
| redis_timeout | number | <pre>false</pre> |  | <pre>2000</pre> |
| redis_database | integer | <pre>false</pre> |  | <pre>0</pre> |
| hide_client_headers | boolean | <pre>true</pre> |  | <pre>true</pre> |
| fallback_enabled | boolean | <pre>true</pre> |  | <pre>false</pre> |
| fallback_by | string | <pre>false</pre> | <pre>- one_of:<br/>  - header</pre> | <pre>header</pre> |
| fallback_header_name | string | <pre>false</pre> |  | <pre>x-client-ip</pre> |
| fallback_window_size | number | <pre>false</pre> | <pre>- gt: 0</pre> |  |
| fallback_limit | number | <pre>false</pre> | <pre>- gt: 0</pre> |  |

## Usage

```yaml
plugins:
  - name: sliding-window-rate-limiting
    enabled: true
    config:
      window_size: 0.0
      limit: 0.0
      limit_by: consumer
      header_name: ''
      path: ''
      policy: redis
      fault_tolerant: true
      redis_host: localhost
      redis_port: 6379
      redis_password: ''
      redis_timeout: 2000
      redis_database: 0
      hide_client_headers: true
      fallback_enabled: false
      fallback_by: header
      fallback_header_name: x-client-ip
      fallback_window_size: 0.0
      fallback_limit: 0.0

```
<!-- END OF KONG-PLUGIN DOCS HOOK -->

More samples configured in [kong.yml](kong.yml)

## Dependencies

Install pongo:

```bash
cd ~
PATH=$PATH:~/.local/bin
git clone git@github.com:Kong/kong-pongo.git
mkdir -p ~/.local/bin
ln -s $(realpath kong-pongo/pongo.sh) ~/.local/bin/pongo
pongo build
```

## Running

- Switch between DBLess or Postgres changing the **DOCKER_COMPOSE_FILE** variable at the `Makefile`
- `make help` to check available commands. Some of them:
  - `make start` to create the rockspec file and start a Kong container to serve the base for the development
  - `make reload` to reload Kong and the chages in plugin's code
  - `make stop` and/or `make clean` to cleaning it up
  - `make lint` and `make test` to run **pongo**
  - With Kong running: `make update_readme` to recreate the section between **KONG-PLUGIN DOCS HOOK** comments
  - `make logs` to check Kong logs
  - `make shell` to access Kong bash
  - `make resty-script` to execute **resty-script.lua** file. Useful to test some code
  - `make build` to generate the **.rock** file at the _./dist_ directory
