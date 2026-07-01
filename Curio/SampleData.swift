import Foundation

// MARK: - Stories
// Real blogs, rewritten from the source files in /content into the Curio format
// per CURIO_BLOG_SPEC.md. Each story has two independent payloads:
//   • CARD  — metadata + `blocks` (collapsed teaser + double-tap inline expand)
//   • READER — `bodyHTML` (full house-styled HTML, in ReaderContent / DetailView.swift)
// TODO: swap this for a real news-API call + Codable mapping (NewsService seam).

let sampleStories: [Story] = [

    // ── ROS (content/ros-explainer.html) ─────────────────────────────────────
    Story(
        id: "ros-nervous-system",
        source: "Kernel",
        mono: "KE",
        category: "ROBOTICS",
        readTime: "5 min",
        author: "Mara Ellison",
        date: "Jun 26, 2026",
        title: "ROS: the nervous system hiding inside almost every robot",
        summary: "Despite the name, it isn't an operating system — and that quiet misnomer hides the cleverest idea in modern robotics.",
        imageURL: "https://images.unsplash.com/photo-1563207153-f403bf289096?w=1000&q=80&auto=format&fit=crop",
        likes: 1_847,
        hue: 0.60,
        chatIntro: "ROS is a publish-subscribe message bus that lets a robot's many programs behave like one mind.",
        blocks: [
            .lead("Say \"operating system\" and you picture Linux or Windows — the thing that owns the hardware. ROS owns none of it. The sneakier trick it pulls instead is why it hides inside almost every research robot on Earth."),
            .paragraph("Picture a robot as a room full of specialists: one program reads the LIDAR, another plans the path, another spins the wheels. **ROS is the protocol that lets them gossip in real time** — none of them knowing, or caring, who the others are."),
            .heading("A phonebook, not a post office"),
            .paragraph("A hidden matchmaker introduces the programs that need each other, then steps out of the way. After that, data flows directly, peer to peer — which is exactly why almost every research robot on Earth runs it."),
            .quote(text: "rosmaster doesn't relay messages. It's a phonebook, not a post office.", cite: nil)
        ],
        prompts: [],
        bodyHTML: ReaderContent.ros
    ),

    // ── OKF (content/okf-reader.html) ────────────────────────────────────────
    Story(
        id: "okf-knowledge-format",
        source: "Google Cloud",
        mono: "GC",
        category: "AI INFRASTRUCTURE",
        readTime: "6 min",
        author: "Sam McVeety",
        date: "Jun 12, 2026",
        title: "Google's fix for AI's dumbest problem is a folder of text files",
        summary: "Models can write code and crunch data — but they're blind to the one thing that makes an answer useful: what your company actually knows. Google's answer isn't a platform. It's a folder of markdown.",
        imageURL: "https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=1000&q=80&auto=format&fit=crop",
        likes: 2_140,
        hue: 0.55,
        chatIntro: "OKF makes organizational knowledge portable across AI agents — as a folder of markdown files, no SDK.",
        blocks: [
            .lead("Foundation models can write code and crunch data in seconds. Ask one how your company defines \"weekly active users,\" though, and it goes quiet — the answer lives in six systems that were never built to talk to each other."),
            .paragraph("That gap is the real bottleneck for enterprise AI. Google's fix is almost cheeky: not a platform, not an API, but **a folder of markdown files** any agent can read, write, and reason over."),
            .quote(text: "LLMs don't get bored, don't forget to update a cross-reference, and can touch 15 files in one pass — exactly the bookkeeping that makes humans abandon wikis.", cite: "Andrej Karpathy")
        ],
        prompts: [],
        bodyHTML: ReaderContent.okf
    ),

    // ── Logto (content/logto-reader.html) ────────────────────────────────────
    Story(
        id: "logto-auth",
        source: "Logto",
        mono: "LO",
        category: "AUTH INFRASTRUCTURE",
        readTime: "7 min",
        author: "The Logto Team",
        date: "May 2026",
        title: "The auth layer your app keeps reinventing — and the open-source one that ends it",
        summary: "Every SaaS needs the same login, SSO, and permissions — and every team burns months rebuilding it, one CVE at a time. Logto is the open-source escape hatch, built on the standards instead of around them.",
        imageURL: "https://images.unsplash.com/photo-1485827404703-89b55fcc595e?w=1000&q=80&auto=format&fit=crop",
        likes: 1_920,
        hue: 0.62,
        chatIntro: "Logto is open-source identity infrastructure — OIDC, SSO, MFA, and RBAC, assembled so you don't have to.",
        blocks: [
            .lead("Every SaaS app needs the same things: sign-in, secure accounts, enterprise SSO, and permissions. None of it is novel — and all of it takes months to build right, with a CVE waiting at every wrong turn."),
            .paragraph("Logto is the open-source escape hatch: a certified OpenID Connect provider you drop in front of your app to get login, passkeys, MFA, SSO, and role-based access — built **on** the standards instead of around them."),
            .heading("Auth is a solved problem nobody wants to solve"),
            .paragraph("Roll your own and you own password hashing, token rotation, PKCE, and SAML flows — each a rabbit hole. Logto ships all of it audited and spec-compliant, so your app stays in the business of being your app.")
        ],
        prompts: [],
        bodyHTML: ReaderContent.logto
    ),

    // ── AI Berkshire (content/ai-berkshire-reader.html) ──────────────────────
    Story(
        id: "ai-berkshire",
        source: "Compound",
        mono: "AB",
        category: "AI INVESTING",
        readTime: "7 min",
        author: "Xibao Lin",
        date: "Jun 2026",
        title: "One person, four dead investors, and a +69% year",
        summary: "A single developer wired Buffett, Munger, and two more investing legends into AI agents built to disagree — then ran real money through it for two years. The track record is the uncomfortable part.",
        imageURL: "https://images.unsplash.com/photo-1501167786227-4cba60f6d58f?w=1000&q=80&auto=format&fit=crop",
        likes: 3_050,
        hue: 0.35,
        chatIntro: "AI Berkshire turns one investor into a research firm — four master methodologies run as agents that argue.",
        blocks: [
            .lead("Ask a chatbot to analyze a stock and you get a balanced, thoughtful essay that ends with \"do your own due diligence\" — useless for an actual decision. One developer decided the problem wasn't the AI. It was the missing discipline."),
            .paragraph("AI Berkshire runs four investing legends — Buffett, Munger, Duan Yongping, Li Lu — as **four AI agents built to disagree**, then forces a real verdict: buy, pass, or an honest grey zone, with price targets."),
            .quote(text: "Price is what you pay, value is what you get.", cite: "Warren Buffett")
        ],
        prompts: [],
        bodyHTML: ReaderContent.aiBerkshire
    ),

    // ── openpilot (content/openpilot-reader.html) ────────────────────────────
    Story(
        id: "openpilot-world-model",
        source: "comma.ai",
        mono: "CA",
        category: "ROBOTICS",
        readTime: "8 min",
        author: "The comma team",
        date: "Mar 2026",
        title: "The $299 gadget that turns your car into a robot — trained inside a dream",
        summary: "openpilot hijacks your car's own controls and hands the driving to a neural net. Its latest release did something stranger: it learned to drive entirely inside a simulation that taught itself the laws of physics from dashcam video.",
        imageURL: "https://images.unsplash.com/photo-1556742049-0cfed4f6a45d?w=1000&q=80&auto=format&fit=crop",
        likes: 4_210,
        hue: 0.58,
        chatIntro: "openpilot replaces your car's driver-assist brain with a neural net — now trained inside a learned world model.",
        blocks: [
            .lead("For $299 and a plug behind your mirror, openpilot hijacks your car's own steering and cruise wiring and hands the driving to a neural network."),
            .paragraph("Its latest release did something stranger still: the driving model learned entirely inside a **simulation that taught itself the laws of physics** from 2.5 million minutes of dashcam video — the first real-world robot shipped to users trained this way."),
            .heading("Not autonomy — a smarter co-pilot"),
            .paragraph("It keeps your hands on the wheel and watches your eyes. Step on the brake and you're instantly back in control. What it replaces is the *brain* behind your car's factory cruise and lane-centering.")
        ],
        prompts: [],
        bodyHTML: ReaderContent.openpilot
    ),

    // ── PhysisForcing (content/physisforcing-reader.html) ────────────────────
    Story(
        id: "physisforcing",
        source: "arXiv",
        mono: "AX",
        category: "AI RESEARCH",
        readTime: "6 min",
        author: "PKU × NVIDIA",
        date: "Jun 2026",
        title: "AI can film a robot doing the impossible — and not notice",
        summary: "The latest video models generate flawless-looking robot footage where objects float and grippers pass through walls. A new paper fixes it not with more data, but by teaching the model exactly where physics lives.",
        imageURL: "https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1000&q=80&auto=format&fit=crop",
        likes: 1_460,
        hue: 0.70,
        chatIntro: "PhysisForcing teaches video models to respect physics by supervising only the regions where interactions happen.",
        blocks: [
            .lead("The best video models can generate footage of a robot picking up an apple that looks completely real — until you step through it frame by frame and watch the apple drift in mid-air and the gripper pass through the table."),
            .paragraph("It's not an ugly video. It's an **impossible** one — and when such videos are used to train robots, the wrong physics teaches the wrong lessons. PhysisForcing fixes it by teaching the model exactly *where* physics lives."),
            .quote(text: "When a model fails on a structured constraint, the fix often isn't more scale — it's supervision aimed where the constraint actually lives.", cite: nil)
        ],
        prompts: [],
        bodyHTML: ReaderContent.physisforcing
    ),

    // ── RCCLX (content/rcclx-reader.html) ────────────────────────────────────
    Story(
        id: "rcclx-meta-amd",
        source: "Meta Engineering",
        mono: "ME",
        category: "GPU INFRASTRUCTURE",
        readTime: "8 min",
        author: "Meta Engineering",
        date: "Feb 24, 2026",
        title: "The 10% speedup hiding between your GPUs, not inside them",
        summary: "The bottleneck in running big AI models isn't the chips — it's the chatter between them. Meta rewrote how AMD GPUs talk to each other and clawed back double-digit latency, with a one-line env var to turn it on.",
        imageURL: "https://images.unsplash.com/photo-1518770660439-4636190af475?w=1000&q=80&auto=format&fit=crop",
        likes: 2_680,
        hue: 0.60,
        chatIntro: "RCCLX is Meta's open-source upgrade to AMD GPU communication — smarter memory access plus FP8 compression.",
        blocks: [
            .lead("Everyone obsesses over how fast AI chips are. The quieter truth: run a big model across dozens of GPUs and up to 30% of the time is spent not computing — just waiting for the chips to talk to each other."),
            .paragraph("Meta went hunting for that lost time on AMD hardware and clawed back a double-digit chunk with two tricks: **read memory directly instead of passing a bucket around a ring**, and compress the data before sending it across the wire."),
            .heading("The bottleneck nobody talks about"),
            .paragraph("A ~10% cut in the delay between words appearing in a chat response — and it comes not from faster chips, but from smarter use of the wires between them.")
        ],
        prompts: [],
        bodyHTML: ReaderContent.rcclx
    ),
]
