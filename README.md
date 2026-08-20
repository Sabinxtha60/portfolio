# Sabin Shrestha — Portfolio Website

A modern, single-page portfolio built from your CV: dark/light theme, glassmorphism
cards, scroll-reveal animations, and a typewriter hero — pure HTML/CSS/JS, no
build step, no framework.

```
sabin-portfolio/
├── index.html
├── css/style.css
├── js/script.js
├── assets/                      # CV PDF + images
├── Dockerfile                   # nginx-based production image
├── nginx/nginx.conf             # gzip, cache headers, /healthz
├── docker-compose.yml           # local dev
├── .github/workflows/deploy.yml # CI/CD pipeline (AWS demo)
├── .github/workflows/pages.yml  # CI/CD pipeline (permanent GitHub Pages host)
├── ecs/task-definition.json     # optional ECS Fargate path
└── aws/*.json                   # IAM policy templates
```

---

## ⚠️ If you're using an AWS Academy Learner Lab account

Read this before wiring up the AWS pipeline. AWS Academy Learner Lab is a
**time-boxed sandbox**, not a normal AWS account, and it cannot host an
always-on site:

- Your session **auto-stops after ~4 hours**, which stops your EC2 instance —
  the site goes offline until you manually restart the lab.
- The AWS credentials it gives you are **temporary and rotate every session**,
  so GitHub secrets built on them go stale in hours.
- Student accounts usually **can't create custom IAM roles or an OIDC
  provider** — which the `deploy.yml` pipeline needs for keyless AWS auth.
- The underlying account can be **reset between terms**, wiping anything
  you created.

**The strategy this repo uses:** GitHub Pages ([`pages.yml`](.github/workflows/pages.yml))
is the **permanent, always-on** host — free, no session limits, deploys on
every push to `main`. The AWS pipeline ([`deploy.yml`](.github/workflows/deploy.yml))
stays as an **on-demand demo** you spin up inside the Learner Lab to show off
the Docker/ECR/EC2 deployment — not something that needs to run 24/7. If you
later get a personal (non-Academy) AWS account, the AWS pipeline works exactly
the same way, permanently.

---

## 0. Permanent hosting: GitHub Pages (do this first)

1. Push this repo to GitHub.
2. In the repo: **Settings → Pages → Source → GitHub Actions**.
3. Push to `main` (or re-run the "Deploy to GitHub Pages" workflow manually
   from the **Actions** tab) — [`pages.yml`](.github/workflows/pages.yml)
   publishes the site automatically.
4. Your live URL appears in the workflow run summary and under
   **Settings → Pages**: `https://<username>.github.io/<repo>/`.

That's it — no AWS, no Docker, no server needed for this path. Every future
`git push` to `main` redeploys it in under a minute.

---

## 1. Run it locally

No build tools needed — just open `index.html`, or serve it properly:

```bash
python -m http.server 8080
# or
npx serve .
```

Then visit `http://localhost:8080`.

---

## 2. Dockerize it

### Step 1 — Install Docker Desktop
Download from https://www.docker.com/products/docker-desktop and confirm it's
running:
```bash
docker --version
```

### Step 2 — Build the image
```bash
cd sabin-portfolio
docker build -t sabin-portfolio:local .
```

### Step 3 — Run it
```bash
docker run -d --name sabin-portfolio -p 8080:80 sabin-portfolio:local
```
Visit `http://localhost:8080`. Check the health endpoint:
```bash
curl http://localhost:8080/healthz
```

### Step 4 — Or use Docker Compose (same result, one command)
```bash
docker compose up --build -d
docker compose down          # stop it
```

The image is a two-layer build: your static files copied onto `nginx:1.27-alpine`,
so the final image is ~15–20MB and needs no runtime dependencies.

---

## 3. Push the image to a registry

You'll push to **Amazon ECR** (used by the CI/CD pipeline below). One-time setup:

```bash
aws ecr create-repository --repository-name sabin-portfolio --region <REGION>

aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com

docker tag sabin-portfolio:local <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/sabin-portfolio:latest
docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/sabin-portfolio:latest
```

---

## 4. Host it on AWS

Two paths are provided. **Path A (recommended for a portfolio site)** is simple
and fits in the AWS Free Tier. **Path B** is the scalable/production pattern if
you want to practice it for your NOC/cloud career goals.

### Path A — EC2 + Docker + CloudFront (recommended, low cost)

**Architecture:** Browser → CloudFront (HTTPS, CDN, free ACM cert) → EC2 running
your Docker container on port 80.

1. **Launch an EC2 instance**
   - AMI: Amazon Linux 2023, type `t2.micro` / `t3.micro` (Free Tier eligible)
   - Security group: allow inbound **80** from CloudFront only (or `0.0.0.0/0`
     to start), and **no inbound 22** — you'll manage it via SSM instead of SSH
   - Attach an IAM instance profile with these managed policies:
     - `AmazonSSMManagedInstanceCore` (lets GitHub Actions deploy via SSM,
       no SSH keys needed)
     - A custom inline policy allowing `ecr:GetAuthorizationToken` and
       `ecr:BatchGetImage`/`GetDownloadUrlForLayer`/`BatchCheckLayerAvailability`
       on your `sabin-portfolio` repo (so the instance can `docker pull`)

2. **Install Docker on first boot** — paste into the instance's **User data**
   field when launching:
   ```bash
   #!/bin/bash
   dnf install -y docker
   systemctl enable --now docker
   ```

3. **First deploy** (manual, one time — after this, CI/CD takes over):
   ```bash
   aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com
   docker run -d --name sabin-portfolio --restart unless-stopped -p 80:80 \
     <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/sabin-portfolio:latest
   ```

4. **Put CloudFront in front of it** (for free HTTPS + a CDN + your custom domain):
   - CloudFront → Create distribution
   - Origin domain: your EC2 public DNS (or an Elastic IP's DNS), HTTP only, port 80
   - Viewer protocol policy: **Redirect HTTP to HTTPS**
   - Request an **ACM certificate** (in `us-east-1`, required for CloudFront) for
     your domain, attach it to the distribution
   - Cache policy: `CachingOptimized` is fine for a static site

5. **Point your domain at it** — in Route 53 (or your registrar), create an
   **A record (Alias)** for your domain → the CloudFront distribution.

Result: `https://yourdomain.com` serves your Dockerized site from EC2, fronted
by CloudFront for TLS + caching, mostly within the AWS Free Tier.

### Path B — ECS Fargate (scalable, no servers to patch)

If you outgrow Path A or want the more "production" pattern:

1. Push your image to ECR (as above).
2. Create an ECS cluster (Fargate launch type).
3. Register the task definition in [`ecs/task-definition.json`](ecs/task-definition.json)
   (fill in your account ID / region).
4. Create an ECS **service** running that task, behind an **Application Load
   Balancer** (ALB) — ACM cert on the ALB listener for HTTPS.
5. Route 53 alias record → ALB.
6. Uncomment the "Option B" block in [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
   and remove the EC2/SSM step so CI/CD deploys to ECS instead.

This costs more (Fargate + ALB have an hourly charge even at idle) but scales
automatically and needs zero OS patching.

---

## 5. CI/CD pipeline (GitHub Actions)

The workflow at [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml)
already does this:

- **Every push / PR:** builds the Docker image and runs a smoke test
  (`curl /healthz` inside the container) — catches broken builds before merge.
- **Push to `main` only:** logs into AWS (via OIDC, no stored AWS keys), builds
  and pushes the image to ECR, then deploys it to your EC2 instance through
  AWS Systems Manager `send-command` (pulls the new image, restarts the
  container). Swap in the ECS block if you're on Path B.

### One-time AWS setup for the pipeline

1. **Create the OIDC identity provider** (lets GitHub Actions assume an AWS
   role without long-lived secrets):
   ```bash
   aws iam create-open-id-connect-provider \
     --url https://token.actions.githubusercontent.com \
     --client-id-list sts.amazonaws.com \
     --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
   ```

2. **Create the deploy role**, trusting only your repo's `main` branch — use
   [`aws/github-oidc-trust-policy.json`](aws/github-oidc-trust-policy.json)
   (fill in your account ID, GitHub username, and repo name) as the trust
   policy, and [`aws/deploy-permissions-policy.json`](aws/deploy-permissions-policy.json)
   as its permissions:
   ```bash
   aws iam create-role \
     --role-name github-actions-sabin-portfolio \
     --assume-role-policy-document file://aws/github-oidc-trust-policy.json

   aws iam put-role-policy \
     --role-name github-actions-sabin-portfolio \
     --policy-name deploy-permissions \
     --policy-document file://aws/deploy-permissions-policy.json
   ```

3. **Add GitHub repo secrets** (Settings → Secrets and variables → Actions):
   | Secret | Value |
   |---|---|
   | `AWS_DEPLOY_ROLE_ARN` | `arn:aws:iam::<ACCOUNT_ID>:role/github-actions-sabin-portfolio` |
   | `EC2_INSTANCE_ID` | e.g. `i-0123456789abcdef0` |

4. Push to `main` — the **Actions** tab shows the pipeline build, push to ECR,
   and deploy in real time.

---

## 6. Custom domain checklist (optional)

- Register a domain (Route 53, Namecheap, etc.)
- Request a free ACM certificate for it — `us-east-1` if fronting with
  CloudFront, or your app's region if using an ALB
- Point an A/ALIAS record at CloudFront (Path A) or the ALB (Path B)
- HTTPS is enforced automatically once the viewer/listener protocol policy is
  set to redirect HTTP → HTTPS

---

## Notes on the CV → site mapping

Every section (About, Skills, Experience, Projects, Education, Certifications,
Contact) was pulled directly from `Sabin_Shrestha_CV.pdf`. To update content
later, edit the relevant `<section>` in `index.html` — no rebuild tooling
required, just redeploy (push to `main` and the pipeline handles the rest).
