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
├── .github/workflows/pages.yml      # CI/CD (permanent GitHub Pages host)
├── .github/workflows/deploy-aws.yml # CI/CD (redeploys the EC2 instance via SSM)
├── infra/cloudformation/            # IaC: EC2 + security group (nginx, cloned from GitHub)
├── ecs/task-definition.json     # optional, advanced: ECS Fargate path
└── aws/*.json                   # optional, advanced: IAM policy templates for a full CI/CD-to-AWS pipeline
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
- Student accounts usually **can't create custom IAM roles**, which rules out
  a fully automated GitHub Actions → AWS pipeline (see §6).
- The underlying account can be **reset between terms**, wiping anything
  you created.

**The strategy this repo uses:** GitHub Pages ([`pages.yml`](.github/workflows/pages.yml))
is the **permanent, always-on** host — free, no session limits, deploys on
every push to `main`. The AWS EC2 setup ([§4](#4-host-it-on-aws-with-cloudformation))
is a CloudFormation template you create fresh each lab session — and once
it's running, [`deploy-aws.yml`](.github/workflows/deploy-aws.yml) *does*
auto-redeploy it on every push, same as Pages, just only for as long as that
session stays active (see [§5](#5-cicd-pipelines-github-actions)).

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

## 3. Push the image to a registry (optional)

The AWS hosting path in §4 below runs nginx **directly on EC2** and clones
the site from GitHub — it doesn't use Docker at all. This step is only
useful if you later want the Docker image itself running somewhere (e.g. a
personal server, or the advanced ECS Fargate path in §6). Push to
**Amazon ECR**:

```bash
aws ecr create-repository --repository-name sabin-portfolio --region <REGION>

aws ecr get-login-password --region <REGION> \
  | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com

docker tag sabin-portfolio:local <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/sabin-portfolio:latest
docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/sabin-portfolio:latest
```

---

## 4. Host it on AWS (with CloudFormation)

**Architecture:** one EC2 instance, nginx installed directly on it (no
Docker), serving the site cloned straight from your GitHub repo on boot.
Everything is declared in [`infra/cloudformation/ec2-nginx.yaml`](infra/cloudformation/ec2-nginx.yaml).
Deliberately ephemeral — no Elastic IP, nothing to preserve. The routine is:
start your lab → create the stack → demo/work → delete the stack (or just let
the lab stop it) → next session, create it again.

### Prerequisite: your repo must be on GitHub and public
The instance runs `git clone` on boot, so push this repo first:
```bash
git add -A
git commit -m "Add CloudFormation EC2 hosting"
git push
```

### Option 1 — AWS Console (easiest, no CLI needed)

1. Open your AWS Academy Learner Lab → **Start Lab** → wait for the green dot
   → click **AWS Details** → **AWS Console** to open the real console in your
   browser (already logged in, no separate login step).
2. In the console, go to **CloudFormation → Stacks → Create stack → With new
   resources (standard)**.
3. **Upload a template file** → choose [`infra/cloudformation/ec2-nginx.yaml`](infra/cloudformation/ec2-nginx.yaml)
   from this repo → **Next**.
4. Stack name: `sabin-portfolio`. Fill in the parameters:
   - **VpcId / SubnetId** — pick the default VPC and any subnet in it from
     the dropdowns
   - **InstanceProfileName** — check **IAM → Roles** in another tab for the
     exact name (commonly `LabInstanceProfile`); leave the default if it
     matches
   - **RepoUrl** — your repo's HTTPS URL, e.g.
     `https://github.com/Sabinxtha60/sabin-portfolio.git`
   - Leave everything else at its default
5. **Next → Next → Submit.** Watch the **Events** tab until status reads
   `CREATE_COMPLETE` (a minute or two).
6. Open the **Outputs** tab → click the `SiteURL` value. Give nginx another
   minute after that if it's not up instantly (it's still cloning/starting).

### Option 2 — AWS CLI (if you have it installed)

```bash
aws cloudformation create-stack \
  --stack-name sabin-portfolio \
  --template-body file://infra/cloudformation/ec2-nginx.yaml \
  --parameters \
      ParameterKey=VpcId,ParameterValue=<your-default-vpc-id> \
      ParameterKey=SubnetId,ParameterValue=<a-subnet-id-in-that-vpc> \
      ParameterKey=InstanceProfileName,ParameterValue=LabInstanceProfile \
      ParameterKey=RepoUrl,ParameterValue=https://github.com/Sabinxtha60/sabin-portfolio.git \
  --region us-east-1

aws cloudformation wait stack-create-complete --stack-name sabin-portfolio --region us-east-1

aws cloudformation describe-stacks --stack-name sabin-portfolio --region us-east-1 \
  --query "Stacks[0].Outputs" --output table
```
(Find `VpcId`/`SubnetId` with `aws ec2 describe-vpcs` / `aws ec2 describe-subnets`
if you don't already know them.)

### Redeploying after you push new commits
Once the stack is up, set up [`deploy-aws.yml`](#5-cicd-pipelines-github-actions)
(§5 below) once and every future `git push` redeploys this instance
automatically — no need to touch CloudFormation again for routine content
updates. Recreating the stack is only for when the instance itself is gone
(lab restarted, or you deleted it on purpose).

### Tearing it down
```bash
aws cloudformation delete-stack --stack-name sabin-portfolio --region us-east-1
```
Or **Console → Stacks → sabin-portfolio → Delete**. Next lab session, create
it again — same template, ~2 minutes, identical result.

---

## 5. CI/CD pipelines (GitHub Actions)

There are two, doing two different jobs:

| Workflow | Triggers on | Does |
|---|---|---|
| [`pages.yml`](.github/workflows/pages.yml) | every push to `main` | Publishes to GitHub Pages — your permanent link. Fully automatic, always works. |
| [`deploy-aws.yml`](.github/workflows/deploy-aws.yml) | every push to `main`, or manually | Tells the **running** EC2 instance (via SSM) to `git pull` + reload nginx. Only works while your Learner Lab session is active. |

### How `deploy-aws.yml` works
1. Looks up the current instance ID from the `sabin-portfolio` CloudFormation
   stack's outputs (so it doesn't matter that the instance ID changes every
   time you recreate the stack).
2. If the stack doesn't exist — lab not started, or you've torn it down —
   the job **exits cleanly, not as a failure**. A green check just means "ran
   fine," a stack-not-found here isn't a bug.
3. If the instance exists, it sends an SSM command to run
   `/usr/local/bin/deploy-site.sh` (baked into the instance by
   `ec2-nginx.yaml`'s `UserData`) — that script does the `git fetch` +
   `git reset --hard` + copy-into-nginx + `systemctl reload nginx`.

### One-time setup: GitHub repo secrets
Since a Learner Lab can't create an OIDC role (see the callout up top), this
uses the temporary credentials from **AWS Details** directly as secrets.
**Settings → Secrets and variables → Actions → New repository secret:**

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | from AWS Academy's "AWS Details" panel |
| `AWS_SECRET_ACCESS_KEY` | from the same panel |
| `AWS_SESSION_TOKEN` | from the same panel |

**These expire when your lab session ends (~4 hours) and rotate every new
session** — update all three secrets each time you start a fresh lab and
want pushes to actually reach AWS. (`gh secret set AWS_ACCESS_KEY_ID` etc.
via the GitHub CLI is faster than the web UI if you're doing this often.)
Forgetting to refresh them just means `deploy-aws.yml` fails with an auth
error — `pages.yml` is completely unaffected either way.

### Day-to-day workflow once both are set up
```bash
git add -A && git commit -m "update projects section" && git push
```
That one push now updates **both** your permanent GitHub Pages site and (if
your lab is running) the live EC2 demo.

---

## 6. Going further (optional, advanced)

Two things are included for later, once you're on a personal AWS account (or
if your course covers them) and want the fuller "production" pattern instead
of the simple EC2+nginx setup above:

- **[`ecs/task-definition.json`](ecs/task-definition.json)** — run the
  Dockerized site (built in §2) on ECS Fargate behind a Load Balancer
  instead of a single EC2 box: scales automatically, no OS patching, costs
  more even at idle.
- **[`aws/*.json`](aws)** — IAM policy templates for a fully automated
  GitHub Actions → AWS pipeline (OIDC role assumption, ECR push, deploy) —
  the kind of setup that needs `iam:CreateRole` permissions a Learner Lab
  account won't grant you, so it only makes sense on a personal account.

### Custom domain checklist (optional)
- Register a domain (Route 53, Namecheap, etc.)
- Put CloudFront or an ALB in front of the EC2 instance/ECS service and
  request a free ACM certificate for your domain
- Point an A/ALIAS record at it
- Set the viewer/listener protocol policy to redirect HTTP → HTTPS

---

## Notes on the CV → site mapping

Every section (About, Skills, Experience, Projects, Education, Certifications,
Contact) was pulled directly from `Sabin_Shrestha_CV.pdf`. To update content
later, edit the relevant `<section>` in `index.html` — no rebuild tooling
required, just redeploy (push to `main` and the pipeline handles the rest).
