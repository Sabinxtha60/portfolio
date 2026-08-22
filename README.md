# Sabin Shrestha — Portfolio Website

A modern, single-page portfolio built from your CV: dark/light theme, glassmorphism
cards, scroll-reveal animations, and a typewriter hero — pure HTML/CSS/JS, no
build step, no framework.

```
sabin-portfolio/
├── index.html
├── css/style.css
├── js/script.js
├── assets/                          # CV PDF + images
├── Dockerfile                       # nginx-based production image
├── nginx/nginx.conf                 # gzip, cache headers, security headers, /healthz
├── docker-compose.yml               # local dev
├── .github/workflows/pages.yml      # CI/CD (permanent GitHub Pages host)
├── .github/workflows/deploy-aws.yml # CI/CD (Docker Hub + SSH deploy to EC2)
└── infra/cloudformation/ec2.yaml    # IaC: VPC + EC2 + Elastic IP (class template, adapted)
```

---

## ⚠️ If you're using an AWS Academy Learner Lab account

AWS Academy Learner Lab is a **time-boxed sandbox**, not a normal AWS
account:

- Your session **auto-stops after ~4 hours**, which stops your EC2 instance
  — the site goes offline until you restart the lab and start the instance
  again.
- Student accounts usually **can't create custom IAM roles**, which would
  rule out an OIDC-based GitHub Actions → AWS pipeline — not a problem here,
  since the pipeline in this repo uses Docker Hub + SSH instead of any AWS
  SDK credentials at all.
- The underlying account can be **reset between terms**, wiping anything
  you created.

**The strategy this repo uses:** GitHub Pages ([`pages.yml`](.github/workflows/pages.yml))
is the **permanent, always-on** host — free, no session limits, deploys on
every push to `main`. The EC2 server ([§4](#4-host-it-on-aws-with-cloudformation))
uses an **Elastic IP**, so as long as the underlying instance is just
*stopped* (not deleted) between lab sessions — which is the normal Learner
Lab behavior — restarting it keeps the same IP and the CI/CD pipeline
([§5](#5-cicd-pipeline-github-actions)) keeps working without touching any
GitHub secrets again.

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

## 3. Push the image to Docker Hub

The AWS pipeline in §5 pulls this image on every deploy, so push it manually
once to confirm it works before wiring up CI/CD:

```bash
docker login -u sabinxtha60
docker tag sabin-portfolio:local sabinxtha60/sabin-portfolio
docker push sabinxtha60/sabin-portfolio
```
(Replace `sabinxtha60` everywhere in this repo with your actual Docker Hub
username if it differs from your GitHub one — it's used in
[`deploy-aws.yml`](.github/workflows/deploy-aws.yml).)

You'll also need a **Docker Hub Access Token** for the pipeline (don't use
your account password): **Docker Hub → Account Settings → Security → New
Access Token** — save it, you'll paste it into a GitHub secret in §5.

---

## 4. Host it on AWS (with CloudFormation)

**Architecture:** a from-scratch VPC (subnet, internet gateway, route table),
one EC2 instance with Docker pre-installed via `UserData`, and an Elastic
IP so the address stays stable across stop/start. Everything is declared in
[`infra/cloudformation/ec2.yaml`](infra/cloudformation/ec2.yaml) — based on
the template provided in class, adapted to auto-install Docker on boot and
personalized to this project.

**Security posture:**
- Security group opens 22 (SSH), 80 (HTTP), 443 (HTTPS) to `0.0.0.0/0` —
  SSH has to stay open to the world here since GitHub-hosted runners don't
  have a fixed IP to allowlist; access is still gated by the PEM key
- IMDSv2 enforced (`MetadataOptions.HttpTokens: required`)
- Root EBS volume encrypted at rest
- nginx (inside the container) sends a locked-down `Content-Security-Policy`
  plus standard hardening headers, and hides its version string

### Step 1 — Create an EC2 key pair (if you don't have one)
AWS Console → **EC2 → Key Pairs → Create key pair** → name it, type
**RSA**, format **.pem** → download it. Keep the `.pem` file — you'll need
it for both direct SSH access and the CI/CD secret in §5.

### Option A — AWS Console (easiest, no CLI needed)
1. Open your AWS Academy Learner Lab → **Start Lab** → wait for the green dot
   → **AWS Details** → **AWS Console**.
2. **CloudFormation → Stacks → Create stack → With new resources (standard)**.
3. **Upload a template file** → choose [`infra/cloudformation/ec2.yaml`](infra/cloudformation/ec2.yaml) → **Next**.
4. Stack name: `sabin-portfolio`. **KeyPair**: pick the key pair from Step 1.
5. **Next → Next → Submit.** Watch **Events** until `CREATE_COMPLETE` (a
   couple of minutes — it's building a full VPC, not just an instance).
6. **Outputs** tab → copy the `ElasticIPPublicIP` value — that's your
   `SERVER_IP` for §5.

### Option B — AWS CLI
```bash
aws cloudformation create-stack \
  --stack-name sabin-portfolio \
  --template-body file://infra/cloudformation/ec2.yaml \
  --parameters ParameterKey=KeyPair,ParameterValue=<your-key-pair-name> \
  --region us-east-1

aws cloudformation wait stack-create-complete --stack-name sabin-portfolio --region us-east-1

aws cloudformation describe-stacks --stack-name sabin-portfolio --region us-east-1 \
  --query "Stacks[0].Outputs" --output table
```

### First-time verification
SSH in directly once to confirm Docker installed correctly (give it a
minute or two after `CREATE_COMPLETE` for `UserData` to finish):
```bash
ssh -i your-key.pem ubuntu@<ElasticIPPublicIP>
docker --version   # should just work, no sudo needed
exit
```

### Redeploying after you push new commits
Once §5's secrets are set up, every `git push` to `main` rebuilds the image,
pushes it to Docker Hub, and SSHes in to restart the container automatically
— you don't touch CloudFormation again for routine content updates.
Recreating the stack is only needed if the instance itself is gone (deleted
on purpose, or the Learner Lab account was reset).

### Tearing it down
```bash
aws cloudformation delete-stack --stack-name sabin-portfolio --region us-east-1
```
Or **Console → Stacks → sabin-portfolio → Delete**.

---

## 5. CI/CD pipeline (GitHub Actions)

Two workflows, two jobs:

| Workflow | Triggers on | Does |
|---|---|---|
| [`pages.yml`](.github/workflows/pages.yml) | every push to `main` | Publishes to GitHub Pages — your permanent link. Always works. |
| [`deploy-aws.yml`](.github/workflows/deploy-aws.yml) | every push to `main` | Builds the Docker image, pushes to Docker Hub, SSHes into the EC2 instance to pull + restart it. |

### How `deploy-aws.yml` works
1. **Build and push** — logs into Docker Hub, builds the image, pushes
   `sabinxtha60/sabin-portfolio`.
2. **Configure SSH** — sets up `~/.ssh` on the runner, disables strict host
   key checking (the instance's host key changes if you ever recreate the
   stack, and this is a short-lived CI runner, not a machine you reuse).
3. **Decode SSH key** — base64-decodes the `SSH_KEY64` secret into a `.pem`
   file used for the SSH steps.
4. **Deploy** — three SSH commands: `docker pull`, then stop+remove the old
   container (tolerant of it not existing yet, for the very first deploy),
   then `docker run` the new one on port 80.

### One-time setup: GitHub repo secrets and variable
**Settings → Secrets and variables → Actions:**

| Type | Name | Value |
|---|---|---|
| Secret | `DOCKERHUB_PAT` | the Docker Hub access token from §3 |
| Secret | `SSH_KEY64` | your `.pem` file's contents, base64-encoded (see below) |
| **Variable** (not secret — click the **Variables** tab) | `SERVER_IP` | the `ElasticIPPublicIP` output from §4 |

Encode the `.pem` file (never paste the raw key contents anywhere, including
here in chat — only the base64 output goes into the GitHub secret):
```bash
# Bash / Git Bash
base64 -w0 your-key.pem   # copy the output, paste as SSH_KEY64
```
```powershell
# PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("your-key.pem"))
```

Unlike an AWS Academy session's temporary credentials, **this key pair and
the Elastic IP don't expire or rotate** — set these three once and pushes
keep working across lab sessions, as long as the stack/instance itself
isn't deleted.

### Day-to-day workflow once it's all set up
```bash
git add -A && git commit -m "update projects section" && git push
```
That one push updates **both** your permanent GitHub Pages site and the live
EC2 server (if the instance is currently running).

---

## 6. Going further (optional)

For later, once you're on a personal AWS account and want the fuller
"production" pattern instead of a single EC2 box: run the same Docker image
on ECS Fargate behind a Load Balancer (scales automatically, no OS
patching), and swap the Docker Hub + SSH pipeline for an OIDC-based GitHub
Actions → AWS one (no stored keys at all). Both need IAM permissions
(`iam:CreateRole`, an OIDC provider) that a Learner Lab account won't grant,
so they only make sense once you're off Academy infrastructure.

### Custom domain checklist (optional)
- Register a domain (Route 53, Namecheap, etc.)
- Put CloudFront or an ALB in front of the EC2 instance and request a free
  ACM certificate for your domain
- Point an A/ALIAS record at it
- Set the viewer/listener protocol policy to redirect HTTP → HTTPS

---

## Notes on the CV → site mapping

Every section (About, Skills, Experience, Projects, Education, Certifications,
Contact) was pulled directly from `Sabin_Shrestha_CV.pdf`. To update content
later, edit the relevant `<section>` in `index.html` — no rebuild tooling
required, just redeploy (push to `main` and the pipeline handles the rest).
