import SwiftUI
import WebKit

struct WebRTCProbeView: NSViewRepresentable {
    var refreshToken: UUID
    var onResult: @MainActor (WebRTCProbePayload) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeNSView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "probe")

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.currentToken = refreshToken
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.currentToken != refreshToken else { return }
        context.coordinator.currentToken = refreshToken
        webView.loadHTMLString(Self.html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var currentToken: UUID?
        private var onResult: @MainActor (WebRTCProbePayload) -> Void

        init(onResult: @escaping @MainActor (WebRTCProbePayload) -> Void) {
            self.onResult = onResult
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let body = message.body as? [String: Any] else { return }

            let supported = body["supported"] as? Bool ?? false
            let error = body["error"] as? String
            let rawBrowser = body["browser"] as? [String: Any] ?? [:]
            let rawHeaders = rawBrowser["httpHeaders"] as? [String: Any] ?? [:]
            let headers = rawHeaders.reduce(into: [String: String]()) { result, item in
                result[item.key] = String(describing: item.value)
            }
            let languages = rawBrowser["languages"] as? [String] ?? []
            let rawCandidates = body["candidates"] as? [[String: Any]] ?? []
            let candidates = rawCandidates.compactMap { item -> WebRTCCandidate? in
                guard let address = item["address"] as? String, !address.isEmpty else {
                    return nil
                }

                return WebRTCCandidate(
                    address: address,
                    type: item["type"] as? String ?? "unknown",
                    transport: item["transport"] as? String ?? "unknown"
                )
            }

            let payload = WebRTCProbePayload(
                supported: supported,
                candidates: Array(Set(candidates)).sorted { $0.id < $1.id },
                browser: BrowserEnvironment(
                    userAgent: rawBrowser["userAgent"] as? String,
                    language: rawBrowser["language"] as? String,
                    languages: languages,
                    timezone: rawBrowser["timezone"] as? String,
                    httpHeaders: headers,
                    error: rawBrowser["error"] as? String
                ),
                error: error
            )

            Task { @MainActor in
                onResult(payload)
            }
        }
    }

    private static let html = """
    <!doctype html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
    </head>
    <body>
      <script>
      (() => {
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.probe;
        const candidates = new Map();
        const browser = {
          userAgent: navigator.userAgent || null,
          language: navigator.language || null,
          languages: Array.isArray(navigator.languages) ? navigator.languages : [],
          timezone: null,
          httpHeaders: {},
          error: null
        };
        let finished = false;
        let iceComplete = !window.RTCPeerConnection;
        let headersComplete = false;
        let peerConnection = null;

        try {
          browser.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || null;
        } catch (error) {
          browser.error = String(error && error.message ? error.message : error);
        }

        function post(payload) {
          if (!handler) { return; }
          handler.postMessage(payload);
        }

        function addCandidate(line) {
          if (!line) { return; }
          const parts = String(line).trim().split(/\\s+/);
          if (parts.length < 6) { return; }

          const typeIndex = parts.indexOf("typ");
          const address = parts[4] || "";
          const transport = parts[2] || "unknown";
          const type = typeIndex >= 0 && parts[typeIndex + 1] ? parts[typeIndex + 1] : "unknown";

          if (!address) { return; }
          const key = `${address}|${type}|${transport}`;
          candidates.set(key, { address, type, transport });
        }

        function finish(pc, error, force = false) {
          if (finished) { return; }
          if (!force && (!iceComplete || !headersComplete)) { return; }
          finished = true;
          try { pc && pc.close(); } catch (_) {}
          post({
            supported: !!window.RTCPeerConnection,
            candidates: Array.from(candidates.values()),
            browser,
            error: error ? String(error) : null
          });
        }

        fetch("https://httpbin.org/headers", { cache: "no-store" })
          .then(response => response.json())
          .then(payload => {
            browser.httpHeaders = payload && payload.headers ? payload.headers : {};
          })
          .catch(error => {
            browser.error = String(error && error.message ? error.message : error);
          })
          .finally(() => {
            headersComplete = true;
            finish(peerConnection, null);
          });

        if (!window.RTCPeerConnection) {
          iceComplete = true;
          finish(null, "RTCPeerConnection unavailable");
          setTimeout(() => finish(null, "RTCPeerConnection unavailable", true), 4500);
          return;
        }

        const pc = new RTCPeerConnection({
          iceServers: [
            { urls: "stun:stun.l.google.com:19302" }
          ]
        });
        peerConnection = pc;

        pc.createDataChannel("probe");
        pc.onicecandidate = event => {
          if (event && event.candidate) {
            addCandidate(event.candidate.candidate);
          }

          if (!event || !event.candidate) {
            iceComplete = true;
            finish(pc, null);
          }
        };

        pc.onicegatheringstatechange = () => {
          if (pc.iceGatheringState === "complete") {
            iceComplete = true;
            finish(pc, null);
          }
        };

        pc.createOffer()
          .then(offer => pc.setLocalDescription(offer))
          .catch(error => {
            iceComplete = true;
            finish(pc, error && error.message ? error.message : error);
          });

        setTimeout(() => finish(pc, null, true), 4500);
      })();
      </script>
    </body>
    </html>
    """
}
