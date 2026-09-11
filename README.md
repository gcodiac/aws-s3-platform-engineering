# Cloud Launchpad

A hands-on cloud and platform engineering project focused on deploying, securing, and automating a static website on AWS.

## AWS Architecture

The production deployment uses a private S3 bucket as the origin, CloudFront as the public entry point, and GitHub Actions CICD to automate deployments.

![AWS static site architecture](assets/images/architecture.svg)

## Live Homepage

The site itself is intentionally simple so the focus stays on the AWS infrastructure, deployment workflow, and platform engineering concepts behind it.

![The Cloud Launchpad homepage](docs/images/homepage.png)

**Follow the course → [https://s3.aliskool.com/](https://s3.aliskool.com/)**

---

## Why AWS for a static site?

A static site does not need AWS.

This exact site can be published in minutes with GitHub Pages, Cloudflare Pages, Netlify or Vercel and the `main` branch is deliberately deployed to GitHub Pages to prove it.

**[View the simple GitHub Pages deployment →](https://gcodiac.github.io/aws-s3-static-site-cicd/)**

The AWS version exists for a different reason: to use a simple application as the vehicle for learning the infrastructure around it.

That means working with:

- private S3 origins
- CloudFront and edge caching
- IAM and least privilege
- TLS certificates
- Terraform
- GitHub Actions
- OIDC-based AWS authentication
- deployment verification

Keeping the application static removes backend complexity, so the focus stays on infrastructure, delivery and automation.

**[Follow the course →](https://s3.aliskool.com/)**

---

## Architecture

```mermaid
flowchart LR
    V["Visitor<br/>browser"] -->|HTTPS| CF["Amazon CloudFront<br/>edge location"]
    CF -->|"signed origin request<br/>(Origin Access Control)"| S3["Amazon S3<br/>private bucket"]
    ACM["AWS Certificate Manager<br/>us-east-1"] -.->|TLS certificate| CF
    X(("Public<br/>internet")) -.->|blocked · 403| S3

    classDef aws fill:#1b2436,stroke:#6ea8ff,color:#e9edfa
    classDef bad  fill:#2a1720,stroke:#ff6b81,color:#ffd7de,stroke-dasharray:4 3
    class CF,S3,ACM aws
    class X bad
```

The bucket is never public. CloudFront is the only thing allowed to read it, and only
for this one distribution — everything else gets `403 AccessDenied`.

---

## What you'll learn

| Topic | Where it shows up |
| --- | --- |
| Amazon S3 | Private origin bucket |
| Amazon CloudFront | CDN, caching, edge HTTPS |
| AWS Certificate Manager | TLS, issued in `us-east-1` |
| Terraform | The infrastructure above, as reviewable code |
| GitHub Actions | CI checks and an automated deployment |
| GitHub OIDC | Temporary AWS credentials — no stored keys |

---

## Run locally

```bash
git clone git@github.com:gcodiac/aws-s3-static-site-cicd.git
cd aws-s3-static-site-cicd

./scripts/serve.sh    # http://localhost:8080
./scripts/test.sh     # static site checks
```

No build step — `serve.sh` wraps `python3 -m http.server`.

---

## Branches

| Branch | Contents |
| --- | --- |
| `main` | This branch. The static site, and nothing else. |
| [`platform-engineering`](../../tree/platform-engineering) | Terraform + CI/CD, fully implemented, with a readable commit history. |

---

## Course

**[Open the Platform Engineering Course →](https://s3.aliskool.com/)**

Step-by-step lessons — S3, CloudFront, ACM, Terraform, GitHub Actions and OIDC — built
around this exact project.

---

## Cost considerations

| Component | Cost consideration |
| --- | --- |
| GitHub Pages | Free for this demo |
| S3 | Very low for a small static site; storage + requests |
| CloudFront | Usage-based requests/data transfer |
| ACM | No separate charge for public certs used with supported AWS services |
| Route 53 | Optional hosted-zone/domain cost |
| CI/CD | GitHub Actions usage depends on plan/runtime |

For a small training site the AWS cost should be low, but resources should still be
destroyed when no longer needed.

---

## Licence

MIT — see [LICENSE](LICENSE).
