import Foundation

// MARK: - Stories
// Real blogs, rewritten from the source files in /content into the Curio format
// per CURIO_BLOG_SPEC.md — kept close to each source's own title and wording.
// Each story has two independent payloads:
//   • CARD  — metadata + `blocks` (collapsed teaser + double-tap inline expand)
//   • READER — `bodyHTML` (full house-styled HTML, in ReaderContent / DetailView.swift)
// TODO: swap this for a real news-API call + Codable mapping (NewsService seam).
// NOTE: the live app fetches from Supabase (see NewsService.swift); this file backs
// MockNewsService (previews / fallback) and should be kept in sync with the DB.

let sampleStories: [Story] = [

    // ── ros-nervous-system ─────────────────────────────────────────────
    Story(
        id: "ros-nervous-system",
        source: "Kernel",
        mono: "KE",
        category: "ROBOTICS",
        readTime: "5 min",
        author: "Mara Ellison",
        date: "Jun 26, 2026",
        title: "ROS is the nervous system of modern robots",
        summary: "A short guide to how ROS connects sensors, brains, and actuators, and why almost every research robot runs it.",
        imageURL: "https://images.unsplash.com/photo-1563207153-f403bf289096?w=1000&q=80&auto=format&fit=crop",
        likes: 1847,
        hue: 0.6,
        chatIntro: "ROS is a publish-subscribe message bus that lets a robot's many programs behave like one mind.",
        blocks: [
            .lead("Despite the name, ROS isn't an operating system like Linux or Windows. It's middleware, a layer that sits on top of Linux and lets separate programs running on a robot talk to each other as if they were one system."),
            .paragraph("Think of a robot as a collection of specialists: one program reads the LIDAR sensor, another runs the path planner, another drives the motors. **ROS is the protocol that lets them exchange data in real time**, without any of them needing to know who the others are."),
            .heading("rosmaster: the matchmaker that stays invisible"),
            .paragraph("When a publisher and subscriber both declare interest in the same topic, rosmaster introduces them, then steps out of the way. After that, messages flow directly between nodes, peer to peer."),
            .quote(text: "rosmaster doesn't relay messages. It's a phonebook, not a post office.", cite: nil),
        ],
        prompts: [],
        bodyHTML: ReaderContent.ros
    ),

    // ── okf-knowledge-format ─────────────────────────────────────────────
    Story(
        id: "okf-knowledge-format",
        source: "Google Cloud",
        mono: "GC",
        category: "AI INFRASTRUCTURE",
        readTime: "6 min",
        author: "Sam McVeety",
        date: "Jun 12, 2026",
        title: "The format that lets AI agents share knowledge",
        summary: "Google introduces OKF, a dead-simple open spec that turns markdown files into a portable knowledge graph any agent can read, write, and reason over.",
        imageURL: "https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=1000&q=80&auto=format&fit=crop",
        likes: 2140,
        hue: 0.55,
        chatIntro: "OKF makes organizational knowledge portable across AI agents — as a folder of markdown files, no SDK.",
        blocks: [
            .lead("Foundation models can write code, summarise documents, and analyse datasets, but only when they have the right context. In most organisations, that context is scattered across systems that were never designed to talk to each other."),
            .paragraph("OKF (Open Knowledge Format) is an open spec for representing the context AI agents need as a directory of **markdown files with YAML frontmatter**. No SDK, no cloud account, no runtime."),
            .quote(text: "LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass, exactly the bookkeeping that makes humans abandon wikis.", cite: "Andrej Karpathy"),
        ],
        prompts: [],
        bodyHTML: ReaderContent.okf
    ),

    // ── logto-auth ─────────────────────────────────────────────
    Story(
        id: "logto-auth",
        source: "Logto",
        mono: "LO",
        category: "AUTH INFRASTRUCTURE",
        readTime: "7 min",
        author: "The Logto Team",
        date: "May 2026",
        title: "The auth layer your SaaS app was missing",
        summary: "Logto is open-source identity infrastructure: OIDC, SSO, multi-tenancy, and RBAC, assembled so you don't have to. Here's how it actually works.",
        imageURL: "https://images.unsplash.com/photo-1485827404703-89b55fcc595e?w=1000&q=80&auto=format&fit=crop",
        likes: 1920,
        hue: 0.62,
        chatIntro: "Logto is open-source identity infrastructure — OIDC, SSO, MFA, and RBAC, assembled so you don't have to.",
        blocks: [
            .lead("Every SaaS app needs the same things: users can sign in, accounts are secure, enterprise customers can use their own identity provider, and different users have different permissions. These are not novel problems, but implementing them correctly takes months."),
            .paragraph("Logto is the open-source, self-hostable answer, built on **OIDC and OAuth 2.1**, the same standards Auth0 and Cognito use, without the cost or the opacity."),
            .heading("Auth is a solved problem nobody wants to solve"),
            .paragraph("Rolling your own means owning sessions, password hashing, token rotation, and SAML flows. Each one is a rabbit hole with a CVE waiting if you get it wrong."),
        ],
        prompts: [],
        bodyHTML: ReaderContent.logto
    ),

    // ── ai-berkshire ─────────────────────────────────────────────
    Story(
        id: "ai-berkshire",
        source: "Compound",
        mono: "AB",
        category: "AI INVESTING",
        readTime: "7 min",
        author: "Xibao Lin",
        date: "Jun 2026",
        title: "One person + Claude = an entire investment team",
        summary: "AI Berkshire systematises the methodologies of Buffett, Munger, Duan Yongping and Li Lu into 16 Claude Code skills, with a live track record of +69% in 2024 and +66% in 2025.",
        imageURL: "https://images.unsplash.com/photo-1501167786227-4cba60f6d58f?w=1000&q=80&auto=format&fit=crop",
        likes: 3050,
        hue: 0.35,
        chatIntro: "AI Berkshire turns one investor into a research firm — four master methodologies run as agents that argue.",
        blocks: [
            .lead("You can ask any LLM to analyse a stock. You'll get a polished, balanced, thoughtful essay that ends with \"investors should conduct their own due diligence\", completely useless for making a decision."),
            .paragraph("AI Berkshire runs four investing legends, **Buffett, Munger, Duan Yongping, Li Lu**, as four AI agents built to disagree, then forces a real verdict: buy, pass, or an honest grey zone, with price targets."),
            .quote(text: "Price is what you pay, value is what you get.", cite: "Warren Buffett"),
        ],
        prompts: [],
        bodyHTML: ReaderContent.aiBerkshire
    ),

    // ── openpilot-world-model ─────────────────────────────────────────────
    Story(
        id: "openpilot-world-model",
        source: "comma.ai",
        mono: "CA",
        category: "ROBOTICS",
        readTime: "8 min",
        author: "The comma team",
        date: "Mar 2026",
        title: "The open-source system turning your car into a robot",
        summary: "What openpilot actually is, how it intercepts your car's own controls, and why the 0.11 release, a driving model trained entirely inside a neural network simulator, marks a quiet milestone in real-world robotics.",
        imageURL: "https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=1000&q=80&auto=format&fit=crop",
        likes: 4210,
        hue: 0.58,
        chatIntro: "openpilot replaces your car's driver-assist brain with a neural net — now trained inside a learned world model.",
        blocks: [
            .lead("openpilot is open-source software that hijacks your car's existing driver-assistance electronics and replaces the decision-making with a neural network, from a $299 plug-in device."),
            .paragraph("Its latest release ships **the first real-world robot agent trained entirely inside a learned simulation**, a breakthrough a decade in the making."),
            .heading("Not a self-driving car, a smarter co-pilot"),
            .paragraph("It keeps your hands on the wheel and your eyes on the road, replacing the brain behind your car's adaptive cruise control and lane centering."),
        ],
        prompts: [],
        bodyHTML: ReaderContent.openpilot
    ),

    // ── physisforcing ─────────────────────────────────────────────
    Story(
        id: "physisforcing",
        source: "arXiv",
        mono: "AX",
        category: "AI RESEARCH",
        readTime: "6 min",
        author: "PKU x NVIDIA",
        date: "Jun 2026",
        title: "Teaching video models to respect physics",
        summary: "PhysisForcing injects hierarchical physics supervision into video diffusion transformers, making robot manipulation videos that are not just visually plausible, but mechanically correct.",
        imageURL: "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1000&q=80&auto=format&fit=crop",
        likes: 1460,
        hue: 0.7,
        chatIntro: "PhysisForcing teaches video models to respect physics by supervising only the regions where interactions happen.",
        blocks: [
            .lead("Video models trained to generate robot manipulation footage still produce physically wrong motion: objects that float, grippers that tunnel through surfaces, grasped items that drift."),
            .paragraph("PhysisForcing fixes this with two training losses focused only on physics-critical regions, **no extra inference cost**, and a jump from 16% to 24% closed-loop planning success."),
            .quote(text: "Physics happens in specific places, around grippers, contact zones, and moving objects, and standard reconstruction losses dilute that signal across the entire frame.", cite: nil),
        ],
        prompts: [],
        bodyHTML: ReaderContent.physisforcing
    ),

    // ── rcclx-meta-amd ─────────────────────────────────────────────
    Story(
        id: "rcclx-meta-amd",
        source: "Meta Engineering",
        mono: "ME",
        category: "GPU INFRASTRUCTURE",
        readTime: "8 min",
        author: "Meta Engineering",
        date: "Feb 24, 2026",
        title: "How Meta made AMD GPUs talk faster to each other",
        summary: "A plain-language walkthrough of RCCLX, Meta's open-source upgrade to GPU communication that cuts AI inference latency by up to 10%.",
        imageURL: "https://images.unsplash.com/photo-1518770660439-4636190af475?w=1000&q=80&auto=format&fit=crop",
        likes: 2680,
        hue: 0.6,
        chatIntro: "RCCLX is Meta's open-source upgrade to AMD GPU communication — smarter memory access plus FP8 compression.",
        blocks: [
            .lead("Training and serving large AI models requires dozens, sometimes thousands, of GPUs working in sync, and collective communication between them can eat up to 30% of total inference time."),
            .paragraph("RCCLX is Meta's open-source upgrade to AMD's GPU communication library: a smarter memory-access algorithm plus a compression trick, cutting latency **without changing your model code**."),
            .heading("Why GPU communication is the bottleneck nobody talks about"),
            .paragraph("On NVIDIA hardware, Meta already had a custom library for this. On AMD, they relied on the stock library, which left a lot of performance on the table."),
        ],
        prompts: [],
        bodyHTML: ReaderContent.rcclx
    ),
]
