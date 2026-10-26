# Runbooks

What to do when an alert fires. Each Slack alert links to its section here.
Commands assume you're in the repo folder of the stack they mention.

## InstanceDown

**Meaning:** Prometheus can't scrape a target for more than 1 minute: the
service is stopped, crashed or unreachable over the Docker network.

**Check:**
- http://localhost:9090/targets shows which target and the scrape error.
- `docker ps -a --filter name=<container>`: is it running, restarting or exited?
- `docker logs <container> --tail 50`: why it stopped.

**Fix:** start it again (`docker compose up -d` in its repo). If it keeps
restarting, the logs say why (for selfapp, usually MySQL or RabbitMQ not
reachable).

## ContainerDown

**Meaning:** `selfdb` (MySQL) or `selfweb` (nginx) hasn't been seen by
cAdvisor for 1 minute. Neither exposes metrics of its own, so this is the
only alert that notices them stopping.

**Check:** `docker ps -a --filter name=selfdb --filter name=selfweb`, then
`docker logs <container> --tail 50`.

**Fix:** `docker compose up -d` in docker-buildlab-selfapp. If MySQL won't
start, check free disk space and the `selfdb-data` volume.

## SelfappHighErrorRate

**Meaning:** more than 5% of requests to the app returned a 5xx error for
5 minutes (health checks and metrics scrapes not counted).

**Check:**
- Grafana → Application Overview → Error Rate: which pages fail.
- Grafana → Explore → Loki: `{container="selfapp"} |= "ERROR"`.
- `curl -s http://localhost/actuator/health`: DOWN means MySQL or RabbitMQ
  is unreachable from the app.

**Fix:** depends on the error in the logs; most often a dependency
(selfdb, selfmq) is down - fix that first.

## SelfappSlowResponses

**Meaning:** the slowest 5% of requests took more than 1 second, for 5
minutes.

**Check:** Request Rate (more traffic than usual?), Container CPU/Memory
for selfapp and selfdb, and HighCPUUsage / HighMemoryUsage alerts.

**Fix:** remove the load or give the app more resources; if one page is
slow on its own, look at its database queries.

## SelfappHighHeapUsage

**Meaning:** the Java heap has been more than 90% full for 10 minutes. The
JVM spends more and more time in garbage collection, and eventually fails
with OutOfMemoryError.

**Check:** `docker logs selfapp | grep -i outofmemory`; is the heap still
growing (a memory leak) or flat at a high level (too small)?

**Fix:** restart selfapp to recover now (`docker compose restart selfapp`);
for a lasting fix, raise the heap (`JAVA_TOOL_OPTIONS=-Xmx...`) or find the
leak.

## RabbitMQNoConsumers

**Meaning:** no consumer is attached to RabbitMQ's queues for 2 minutes:
selfapp's `user.created` listener isn't running, so events wait unprocessed.

**Check:** is selfapp running? `docker logs selfapp | grep -i rabbit` for
connection errors; http://localhost:15672 → Queues → `user.created` →
Consumers.

**Fix:** restart selfapp; check `MQ_USER` / `MQ_PASS` in the app's `.env`
match RabbitMQ's.

## RabbitMQMessagesPilingUp

**Meaning:** more than 100 messages have been waiting in the queues for 5
minutes: they arrive faster than the consumer handles them, or it's stuck.

**Check:** RabbitMQ UI (http://localhost:15672) → Queues: message rates in
and out; RabbitMQNoConsumers firing too?

**Fix:** restart a stuck consumer; if it's just slow, it catches up once
the burst ends.

## HighCPUUsage

**Meaning:** the host's CPU has been more than 80% busy for 2 minutes. On
Docker Desktop, "host" is Docker's Linux VM, not your whole Mac.

**Check:** Grafana → System Overview, and `docker stats --no-stream` to
find the busy container.

**Fix:** stop what's using it (`./scripts/simulate-incident.sh cpu` causes
this on purpose and stops by itself).

## HighMemoryUsage

**Meaning:** less than 10% of the host's memory has been available for 5
minutes. Containers may soon be killed by the kernel's out-of-memory killer.

**Check:** `docker stats --no-stream` (MEM USAGE column).

**Fix:** stop containers you don't need, or give Docker Desktop more memory
(Settings → Resources).

## LowDiskSpace

**Meaning:** less than 10% free space on the host's disk. Prometheus, Loki
and MySQL stop writing when it's full.

**Check:** `docker system df` for Docker's share.

**Fix:** `docker builder prune` and `docker image prune` are safe; remove
unused volumes only after checking what's in them.
