import SwiftUI
import WebKit

// MARK: - DetailView (premium HTML reader)
// The article body is real HTML rendered in a WKWebView with the Curio house
// stylesheet — so it can show anything the web can (rich text, lists, tables,
// figures, code, blockquotes, and custom SVG/canvas/JS visualizations) while
// staying consistently premium and on-brand. Hero + byline + body all live in
// the web layer (one scroll surface); the back chevron, reading-progress bar,
// and the swipe morph transition stay native. Dismiss-swipe is a UIKit pan on
// the web view's scroll view (gated to rightward-horizontal) so vertical
// reading never contends with it.
struct DetailView: View {
    let story: Story
    let onCloseDragChanged: (CGFloat) -> Void
    let onCloseDragEnded: (CGFloat, CGFloat) -> Void
    let onClose: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.safeTop) private var safeTop
    @Environment(\.safeBottom) private var safeBottom
    @State private var readProgress: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                theme.pageBg.ignoresSafeArea()

                WebArticleView(
                    html: ReaderHTML.page(for: story, safeTop: safeTop, safeBottom: safeBottom),
                    onScrollProgress: { readProgress = $0 },
                    onCloseDragChanged: onCloseDragChanged,
                    onCloseDragEnded: onCloseDragEnded
                )
                .ignoresSafeArea()

                // Reading-progress bar, pinned to the very top.
                Rectangle()
                    .fill(theme.accent)
                    .frame(width: max(0, geo.size.width * readProgress), height: 2.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)

                // Always-available way back (in addition to swipe-right).
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.16), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
                .padding(.top, safeTop + 4)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - WebArticleView (WKWebView wrapper)
private struct WebArticleView: UIViewRepresentable {
    let html: String
    let onScrollProgress: (CGFloat) -> Void
    let onCloseDragChanged: (CGFloat) -> Void
    let onCloseDragEnded: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.isOpaque = false
        web.backgroundColor = UIColor(red: 8/255, green: 9/255, blue: 11/255, alpha: 1)   // pageBg
        web.scrollView.backgroundColor = web.backgroundColor
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.contentInsetAdjustmentBehavior = .never   // hero sits under the status bar
        web.scrollView.delegate = context.coordinator
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = false

        // Dismiss-swipe as a UIKit pan so it never fights vertical reading scroll.
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleClosePan(_:)))
        pan.delegate = context.coordinator
        web.scrollView.addGestureRecognizer(pan)

        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }   // only reload on real change
        context.coordinator.loadedHTML = html
        web.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, WKNavigationDelegate, UIGestureRecognizerDelegate {
        let parent: WebArticleView
        var loadedHTML: String?
        init(_ parent: WebArticleView) { self.parent = parent }

        func scrollViewDidScroll(_ sv: UIScrollView) {
            let scrollable = max(sv.contentSize.height - sv.bounds.height, 1)
            parent.onScrollProgress(min(1, max(0, sv.contentOffset.y / scrollable)))
        }

        @objc func handleClosePan(_ g: UIPanGestureRecognizer) {
            let v = g.view
            let tx = g.translation(in: v).x
            switch g.state {
            case .began, .changed:
                parent.onCloseDragChanged(tx)
            case .ended, .cancelled, .failed:
                parent.onCloseDragEnded(tx, g.velocity(in: v).x)
            default:
                break
            }
        }

        // Only begin for a clearly-rightward horizontal drag → vertical reading wins.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return true }
            let vel = pan.velocity(in: pan.view)
            return vel.x > 0 && abs(vel.x) > abs(vel.y) * 1.2
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - ReaderHTML (page assembly + house stylesheet)
enum ReaderHTML {

    /// Assemble the full reader page: house CSS + masthead (from card metadata) + body.
    static func page(for story: Story, safeTop: CGFloat, safeBottom: CGFloat) -> String {
        let body = story.bodyHTML ?? html(from: story.blocks)
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>\(css(safeBottom: safeBottom))</style>
        </head>
        <body>
          <div class="hero"><img src="\(story.imageURL)" alt=""></div>
          <div class="masthead">
            <div class="eyebrow">\(esc(story.category))</div>
            <h1 class="title">\(esc(story.title))</h1>
            <div class="byline">
              <div class="chip">\(esc(story.mono))</div>
              <div class="who">
                <div class="author">\(esc(story.author))</div>
                <div class="meta">\(esc(story.source)) &middot; \(esc(story.date)) &middot; \(esc(story.readTime)) read</div>
              </div>
            </div>
          </div>
          <div class="rule"></div>
          <article class="body">\(body)</article>
        </body>
        </html>
        """
    }

    // MARK: House stylesheet — dark, Curio fonts, premium reading defaults.
    private static func css(safeBottom: CGFloat) -> String {
        """
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-ExtraBold.ttf'); font-weight:800; font-display:swap; }
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-Bold.ttf');      font-weight:700; font-display:swap; }
        @font-face { font-family:'Schibsted'; src:url('SchibstedGrotesk-SemiBold.ttf');  font-weight:600; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Regular.ttf');  font-weight:400; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Medium.ttf');   font-weight:500; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-SemiBold.ttf'); font-weight:600; font-display:swap; }
        @font-face { font-family:'Hanken'; src:url('HankenGrotesk-Bold.ttf');     font-weight:700; font-display:swap; }

        :root {
          --bg:#08090B; --surface:#101216; --elevated:#1A1D23;
          --text:#F4F5F6; --sub:rgba(255,255,255,.62); --faint:rgba(255,255,255,.40);
          --line:rgba(255,255,255,.09); --accent:#6AA0FF;
          --sans:'Hanken',-apple-system,system-ui,sans-serif;
          --display:'Schibsted','Hanken',-apple-system,sans-serif;
          --mono:ui-monospace,'SF Mono',Menlo,monospace;
          --sb:\(Int(safeBottom))px;
        }
        * { margin:0; padding:0; box-sizing:border-box; -webkit-text-size-adjust:100%; }
        html,body { background:var(--bg); }
        body { font-family:var(--sans); color:var(--text); line-height:1.72;
               -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility; }
        img { max-width:100%; }

        .hero { position:relative; width:100%; height:42vh; background:var(--elevated); overflow:hidden; }
        .hero img { width:100%; height:100%; object-fit:cover; display:block; }
        .hero::after { content:''; position:absolute; inset:0; pointer-events:none;
          background:linear-gradient(to bottom, rgba(8,9,11,.42) 0, rgba(8,9,11,0) 20%,
                     rgba(8,9,11,0) 52%, var(--bg) 100%); }

        .masthead { padding:22px 22px 0; }
        .eyebrow { font-family:var(--mono); font-size:11px; font-weight:600; letter-spacing:.18em;
          color:var(--accent); text-transform:uppercase; }
        h1.title { font-family:var(--display); font-weight:800; font-size:32px; line-height:1.12;
          letter-spacing:-.02em; margin-top:12px; }
        .byline { display:flex; align-items:center; gap:11px; margin-top:18px; }
        .byline .chip { width:36px; height:36px; border-radius:9px; background:var(--elevated);
          display:flex; align-items:center; justify-content:center; font-weight:700; font-size:12.5px; }
        .byline .author { font-weight:600; font-size:14.5px; }
        .byline .meta { font-size:12.5px; color:var(--faint); margin-top:3px; }
        .rule { height:1px; background:var(--line); margin:20px 22px 0; }

        .body { padding:26px 22px calc(90px + var(--sb)); font-size:17.5px; }
        .body > * + * { margin-top:22px; }
        .body p { color:rgba(244,245,246,.92); line-height:1.75; }
        .body .lead { font-size:20px; font-weight:500; line-height:1.62; color:var(--text); }
        h2 { font-family:var(--display); font-weight:700; font-size:23px; line-height:1.25;
          letter-spacing:-.01em; margin-top:38px; }
        h3 { font-family:var(--display); font-weight:600; font-size:19px; margin-top:30px; }
        .body strong { font-weight:700; color:var(--text); }
        .body em { font-style:italic; }
        .body a { color:var(--accent); text-decoration:none; border-bottom:1px solid rgba(106,160,255,.35); }
        .body ul, .body ol { padding-left:22px; }
        .body li { margin-top:9px; line-height:1.68; color:rgba(244,245,246,.9); }
        .body li::marker { color:var(--accent); }

        blockquote { border-left:3px solid var(--accent); padding-left:18px; }
        blockquote p { font-family:var(--display); font-weight:600; font-size:21px; line-height:1.4; color:var(--text); }
        blockquote cite { display:block; margin-top:10px; font-family:var(--mono); font-size:10.5px;
          letter-spacing:.06em; color:var(--accent); font-style:normal; text-transform:uppercase; }

        figure { margin:0; }
        figure img { width:100%; border-radius:14px; border:1px solid var(--line); display:block; }
        figcaption { font-size:13px; color:var(--faint); font-style:italic; margin-top:10px; }

        table { width:100%; border-collapse:collapse; font-size:13.5px; border:1px solid var(--line);
          border-radius:14px; overflow:hidden; }
        thead { background:var(--elevated); }
        th,td { text-align:left; padding:11px 13px; border-bottom:1px solid var(--line); }
        th { font-weight:700; } td { color:var(--sub); }
        th:first-child, td:first-child { color:var(--text); }
        tr:last-child td { border-bottom:none; }

        pre { background:var(--surface); border:1px solid var(--line); border-radius:12px; padding:16px;
          overflow-x:auto; font-family:var(--mono); font-size:13px; line-height:1.6; color:#c9d3e6; }
        p code, li code { background:var(--elevated); padding:2px 6px; border-radius:5px;
          font-family:var(--mono); font-size:.85em; color:#cdd6f4; }
        hr { border:none; height:1px; background:var(--line); margin:34px 0; }

        /* helper: callout box */
        .callout { background:var(--surface); border:1px solid var(--line); border-radius:14px; padding:18px 20px; }
        .callout > * + * { margin-top:10px; }
        .callout .k { font-family:var(--mono); font-size:11px; letter-spacing:.1em; color:var(--accent);
          text-transform:uppercase; }
        .callout ol, .callout ul { padding-left:20px; }
        /* helper: custom-visualization container (canvas / svg / bespoke widgets) */
        .viz { background:var(--surface); border:1px solid var(--line); border-radius:16px; padding:20px; overflow:hidden; }
        .viz .cap { font-family:var(--mono); font-size:11px; letter-spacing:.08em; color:var(--faint);
          text-transform:uppercase; margin-top:14px; }
        """
    }

    // MARK: Fallback — render a story's `blocks` as house HTML when bodyHTML is nil.
    static func html(from blocks: [ArticleBlock]) -> String {
        blocks.map { block in
            switch block {
            case .lead(let t):
                return "<p class=\"lead\">\(inline(t))</p>"
            case .heading(let t):
                return "<h2>\(esc(t))</h2>"
            case .paragraph(let t):
                return "<p>\(inline(t))</p>"
            case .quote(let t, let cite):
                let c = cite.map { "<cite>\(esc($0))</cite>" } ?? ""
                return "<blockquote><p>\(esc(t))</p>\(c)</blockquote>"
            case .image(let url, let caption):
                let cap = caption.map { "<figcaption>\(esc($0))</figcaption>" } ?? ""
                return "<figure><img src=\"\(url)\" alt=\"\">\(cap)</figure>"
            case .table(let head, let rows):
                let th = head.map { "<th>\(esc($0))</th>" }.joined()
                let body = rows.map { r in "<tr>" + r.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined()
                return "<table><thead><tr>\(th)</tr></thead><tbody>\(body)</tbody></table>"
            case .diagram(let title, let steps):
                let head = title.map { "<div class=\"k\">\(esc($0))</div>" } ?? ""
                let items = steps.map { "<li>\(inline($0))</li>" }.joined()
                return "<div class=\"callout\">\(head)<ol>\(items)</ol></div>"
            }
        }.joined(separator: "\n")
    }

    // MARK: Text helpers
    /// HTML-escape plain text.
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// Escape, then convert inline markdown (**bold**, *italic*, [link](url)) to HTML.
    static func inline(_ s: String) -> String {
        var out = esc(s)
        out = regexReplace(out, #"\[([^\]]+)\]\(([^)]+)\)"#, "<a href=\"$2\">$1</a>")
        out = regexReplace(out, #"\*\*([^*]+)\*\*"#, "<strong>$1</strong>")
        out = regexReplace(out, #"\*([^*]+)\*"#, "<em>$1</em>")
        return out
    }

    private static func regexReplace(_ s: String, _ pattern: String, _ template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return re.stringByReplacingMatches(in: s, range: range, withTemplate: template)
    }
}

// MARK: - Flagship reader content
// A fully-authored house-styled article that exercises every element in the
// toolbox — the reference example the authoring spec points to.
enum ReaderContent {
    static let neuroChips = #"""
    <p class="lead">A single GPT-4-class training run consumes more electricity than 130 American homes use in a year — and the next generation will need four times that. A handful of chipmakers are betting the fix isn't more silicon, but silicon that thinks like a brain.</p>

    <p>For eighty years, nearly every computer ever built has obeyed the same blueprint: memory in one place, compute in another, and a bus shuttling data between them. It is called the <strong>von Neumann architecture</strong>, and for AI workloads it has quietly become the enemy.</p>

    <h2>The von Neumann wall</h2>
    <p>Every modern accelerator — Nvidia's H100, Google's TPU, Amazon's Trainium — spends most of its energy not on math but on <em>movement</em>: hauling weights from memory to the compute units and back, billions of times a second. Researchers call this the <a href="#">memory wall</a>, and it now dominates the power budget of large models.</p>

    <blockquote>
      <p>We are not making a faster GPU. We are making a different animal entirely.</p>
      <cite>Dr. Kwabena Boahen · Stanford Neurogrid Lab</cite>
    </blockquote>

    <p>Neuromorphic chips attack the wall with three ideas borrowed from biology:</p>
    <ul>
      <li><strong>In-memory compute</strong> — the math happens where the weights already live, so data barely moves.</li>
      <li><strong>Event-driven spikes</strong> — neurons fire only when they have something to say; the rest of the chip sits dark.</li>
      <li><strong>Massive parallelism</strong> — hundreds of thousands of tiny cores, each doing almost nothing, almost all the time.</li>
    </ul>

    <figure>
      <img src="https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?w=1000&q=80&auto=format&fit=crop" alt="Neuromorphic wafer">
      <figcaption>A wafer of neuromorphic cores under inspection at a fabrication lab in Hillsboro, Oregon.</figcaption>
    </figure>

    <h2>Spikes, not floats</h2>
    <p>Biological neurons don't stream 32-bit numbers. They fire discrete voltage spikes — and only when a threshold is crossed. <strong>Spiking Neural Networks</strong> mimic this: between spikes, most transistors draw near-zero power. The efficiency gap is not incremental.</p>

    <div class="viz">
      <svg viewBox="0 0 320 150" width="100%" role="img" aria-label="Energy per inference by chip">
        <line x1="14" y1="120" x2="306" y2="120" stroke="rgba(255,255,255,.12)"/>
        <rect x="34"  y="20"  width="52" height="100" rx="5" fill="#6AA0FF"/>
        <rect x="134" y="86"  width="52" height="34"  rx="5" fill="#6AA0FF" opacity="0.5"/>
        <rect x="234" y="104" width="52" height="16"  rx="5" fill="#6AA0FF" opacity="0.35"/>
        <text x="60"  y="138" fill="rgba(255,255,255,.6)" font-size="11" text-anchor="middle" font-family="monospace">H100</text>
        <text x="160" y="138" fill="rgba(255,255,255,.6)" font-size="11" text-anchor="middle" font-family="monospace">Loihi</text>
        <text x="260" y="138" fill="rgba(255,255,255,.6)" font-size="11" text-anchor="middle" font-family="monospace">Akida</text>
      </svg>
      <div class="cap">Relative energy per inference — lower is better</div>
    </div>

    <h3>How a spiking neuron fires</h3>
    <ol>
      <li>Dendrites accumulate weighted input from upstream neurons.</li>
      <li>The membrane potential climbs toward a <strong>threshold voltage</strong>.</li>
      <li>At threshold the neuron emits a single <strong>spike</strong> — a ~1 ms pulse.</li>
      <li>Local potential resets to zero; the transistor goes fully idle.</li>
    </ol>

    <h2>The software problem</h2>
    <p>Hardware is the easy part. The hard part is rewriting decades of frameworks — <code>PyTorch</code> and <code>JAX</code> have no native concept of a spike. A minimal training step looks less like matrix multiplication and more like a physics loop:</p>

    <pre><code>for t in range(T):
    mem += W @ spikes_in        # integrate
    spikes_out = mem > threshold # fire
    mem[spikes_out] = 0          # reset</code></pre>

    <div class="callout">
      <div class="k">The bottom line</div>
      <p>If spiking-network compilers reach production quality before the next GPU generation ships, the 2030 data-centre could look radically different — quieter, cooler, and drawing a fraction of the power. If they don't, brute-force silicon wins another round.</p>
    </div>

    <p>Either way, the industry has finally admitted the uncomfortable truth: the way we compute, not just how fast, is now the thing standing between us and the next model.</p>
    """#
}

#Preview {
    DetailView(story: sampleStories[0],
               onCloseDragChanged: { _ in },
               onCloseDragEnded: { _, _ in },
               onClose: {})
        .environment(\.theme, .dark)
        .environment(\.safeTop, 59)
        .environment(\.safeBottom, 34)
        .preferredColorScheme(.dark)
}
