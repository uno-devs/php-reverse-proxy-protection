# php-reverse-proxy-protection

Non-root Nginx reverse proxy (`nginx-unprivileged`, uid 101, port 8080) that sits in front of
PHP deployments you can't upgrade yet and filters the request shapes that trigger
**PHP2Shell** (CVE-2026-109618 / CVE-2026-109619, unauthenticated RCE in PHP core; fixed in
PHP 8.5.12, 8.4.27, 8.3.36, 8.2.35 on 2026-10-21).

**This is a stopgap, not a fix.** Patch when you can, then restart every PHP worker.

## What it does

| Control | Why |
|---|---|
| Rejects any `Content-Type` containing `multipart` (case-insensitive) with 403 | Confirmed trigger path for both CVEs (multipart parsing, `PHP_SESSION_UPLOAD_PROGRESS`) |
| `UPLOAD_PATHS` allowlist for real upload endpoints | Those endpoints stay exposed until you patch |
| `client_max_body_size` (default 8m), also enforced on chunked bodies; bodies are buffered so PHP always gets a Content-Length | Limits the memory-exhaustion path (CVE-2026-109618) |
| Pins `Content-Type` to the single inspected value | Stops duplicate-header smuggling past the filter |
| Method allowlist, small header buffers, short timeouts | General hardening |
| read-only rootfs, `cap_drop: ALL`, `no-new-privileges` (see compose file) | Container hardening |

## Usage

```sh
docker build -t php-proxy .
docker run -p 8080:8080 --read-only --tmpfs /tmp --tmpfs /etc/nginx/conf.d --cap-drop ALL \
  -e UPSTREAM=http://my-php:80 -e UPLOAD_PATHS=/upload.php,/api/avatar php-proxy
```

Make the PHP backend reachable **only** through the proxy; otherwise the filter is bypassable.

## Settings the proxy cannot do for you (set on the PHP side)

- `session.upload_progress.enabled=0` in php.ini / FPM pool (not `ini_set` or `.user.ini`)
- PHP 8.5 only: `fatal_error_backtraces=0`
- mod_php: `memory_limit=-1`, and contain PHP with a container/cgroup memory limit (not RLIMIT_AS/DATA)
- `post_max_size` of 8M (32M if uploads are needed)
- Remove `php_value`/`php_flag` or `fastcgi_param PHP_VALUE` entries that emit warnings

## Limits

- Allowlisted upload paths remain exploitable.
- Attacker-triggerable fatal errors/timeouts in your app (CVE-2026-109619 path) can't be filtered here.
- Reports conflict on mod_php vs PHP-FPM exposure; assume both are affected.

## Test

`test/run.sh` builds the image, runs it against a stub backend and asserts the filtering
(needs a running Docker daemon). Not yet run on this machine, since no daemon was available.

Sources: [Ma.ttias.be mitigation notes](https://ma.ttias.be/php-cve-2026-109618-early-mitigation/),
[Talos](https://blog.talosintelligence.com/two-critical-rces-in-php-core/),
[PHP Foundation](https://thephp.foundation/blog/2026/10/21/todays-php-security-release-and-how-were-strengthening-php-security/).
