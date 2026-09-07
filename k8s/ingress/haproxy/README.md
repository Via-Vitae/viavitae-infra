# k8s/ingress/haproxy

HAProxy configuration for the platform. HAProxy runs on the load balancer VMs
(lb-01, lb-02) and terminates TLS before forwarding to the in-cluster Traefik
ingress controller.

## What is not configured here

- TLS certificates. That is cert-manager's job.
- Backend routing. That is Traefik's job.
- Rate limiting. That is Traefik's job.

## What is configured here

- TLS termination parameters (cipher suites, protocol versions).
- Health checks for the Traefik backends.
- Logging format.
