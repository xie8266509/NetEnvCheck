import Foundation

enum RemediationCategory: String, Sendable {
    case network
    case browser
    case system
    case identity
    case data

    var title: String {
        switch self {
        case .network:
            "网络出口"
        case .browser:
            "浏览器信号"
        case .system:
            "系统设置"
        case .identity:
            "IP 情报"
        case .data:
            "检测数据"
        }
    }

    var symbolName: String {
        switch self {
        case .network:
            "network"
        case .browser:
            "globe"
        case .system:
            "gearshape"
        case .identity:
            "shield.lefthalf.filled"
        case .data:
            "server.rack"
        }
    }
}

enum RemediationDifficulty: String, Sendable {
    case easy
    case medium
    case hard

    var title: String {
        switch self {
        case .easy:
            "容易"
        case .medium:
            "中等"
        case .hard:
            "较难"
        }
    }
}

enum RemediationSafetyLevel: String, Sendable {
    case safe
    case manual
    case admin

    var title: String {
        switch self {
        case .safe:
            "安全"
        case .manual:
            "需手动确认"
        case .admin:
            "可能需要管理员权限"
        }
    }
}

enum RemediationActionKind: Sendable {
    case openSettings(SystemSettingsDestination)
    case copyCommand(String)
    case copyGuide(String)
    case copyText(String)
    case refresh
    case markHandled
}

struct RemediationAction: Identifiable, Sendable {
    var id: String
    var title: String
    var systemImage: String
    var kind: RemediationActionKind
    var safety: RemediationSafetyLevel
}

struct RemediationPlan: Identifiable, Sendable {
    var id: String
    var title: String
    var summary: String
    var whyItMatters: String
    var category: RemediationCategory
    var difficulty: RemediationDifficulty
    var safety: RemediationSafetyLevel
    var estimatedScoreGain: Int
    var relatedImpactIDs: [String]
    var steps: [String]
    var actions: [RemediationAction]
}

enum RemediationEngine {
    static func plans(for report: CheckReport) -> [RemediationPlan] {
        let impacts = Dictionary(uniqueKeysWithValues: report.scoreBreakdown.map { ($0.id, $0) })
        let impactIDs = Set(impacts.keys)
        var plans: [RemediationPlan] = []

        func gain(_ ids: [String]) -> Int {
            ids.compactMap { impacts[$0]?.points }
                .map(abs)
                .reduce(0, +)
        }

        func append(_ plan: RemediationPlan) {
            guard plan.relatedImpactIDs.contains(where: impactIDs.contains) else { return }
            plans.append(plan)
        }

        append(
            RemediationPlan(
                id: "public-ip",
                title: "恢复公网 IP 检测",
                summary: "核心接口没有拿到公网 IP，先确认网络连通性和代理状态。",
                whyItMatters: "公网 IP 是归属地、ASN、代理识别和后续评分的基础，缺失时所有结论都会变弱。",
                category: .data,
                difficulty: .easy,
                safety: .safe,
                estimatedScoreGain: gain(["public-ip"]),
                relatedImpactIDs: ["public-ip"],
                steps: [
                    "确认当前网络可以访问外网，并且代理或防火墙没有拦截公开 IP 查询接口。",
                    "如果正在切换网络或代理，等待连接稳定后重新检测。",
                    "必要时打开网络设置检查 Wi-Fi、以太网或 VPN 状态。"
                ],
                actions: [
                    .openNetwork,
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "datacenter",
                title: "更换住宅或移动出口",
                summary: "当前出口被识别为托管、云服务或机房网络。",
                whyItMatters: "很多服务会把数据中心 ASN 视为批量注册、自动化或代理环境，容易提高风控敏感度。",
                category: .identity,
                difficulty: .hard,
                safety: .manual,
                estimatedScoreGain: gain(["datacenter"]),
                relatedImpactIDs: ["datacenter"],
                steps: [
                    "优先使用真实家庭宽带、办公网络或移动热点出口。",
                    "如果必须使用代理，选择归属地稳定、ASN 与目标场景一致的出口。",
                    "更换出口后重新检测，确认 ASN 和 IP 类型不再显示为 hosting 或数据中心。"
                ],
                actions: [
                    .copyGuide(
                        id: "copy-datacenter-guide",
                        title: "复制更换出口指南",
                        guide: """
                        NetEnvCheck 优化建议：当前出口 IP 位于数据中心或托管网络。

                        建议：
                        1. 更换为住宅宽带、办公网络或移动热点出口。
                        2. 避免使用云服务器、机房、VPS、公开代理池出口。
                        3. 更换后重新检测 ASN、IP 类型和代理识别结果。
                        """
                    ),
                    .openNetwork,
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "proxy-vpn-tor",
                title: "降低代理/VPN/Tor 特征",
                summary: "公开情报源命中了代理、VPN 或 Tor 信号。",
                whyItMatters: "这类信号通常来自 IP 情报库，单靠本机设置很难清除，需要更换出口或调整代理链路。",
                category: .identity,
                difficulty: .hard,
                safety: .manual,
                estimatedScoreGain: gain(["proxy", "vpn", "tor"]),
                relatedImpactIDs: ["proxy", "vpn", "tor"],
                steps: [
                    "确认是否开启了系统代理、VPN、Tor 或代理客户端。",
                    "更换节点后等待 IP 情报源更新，并重新检测。",
                    "如果目标服务偏好低风险环境，优先使用非共享、非公开代理池出口。"
                ],
                actions: [
                    .copyCommand(
                        id: "copy-proxy-status",
                        title: "复制代理检查命令",
                        command: "scutil --proxy"
                    ),
                    .openVPN,
                    .copyGuide(
                        id: "copy-proxy-guide",
                        title: "复制代理优化指南",
                        guide: """
                        NetEnvCheck 优化建议：当前出口命中代理/VPN/Tor 信号。

                        建议：
                        1. 检查系统代理、VPN、Tor、代理客户端是否开启。
                        2. 更换为更干净、共享程度更低、归属地稳定的出口。
                        3. 避免多层代理链路导致 DNS、WebRTC、时区和语言信号互相冲突。
                        """
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "system-proxy",
                title: "核对系统代理配置",
                summary: "系统代理处于启用状态，需要确认代理协议、DNS 和浏览器出口是否一致。",
                whyItMatters: "系统代理、浏览器代理和 DNS 如果没有走同一条链路，会形成混合环境信号。",
                category: .network,
                difficulty: .medium,
                safety: .manual,
                estimatedScoreGain: gain(["system-proxy"]),
                relatedImpactIDs: ["system-proxy"],
                steps: [
                    "打开网络设置，确认当前代理是否为你预期使用的代理。",
                    "运行 scutil --proxy 查看 HTTP、HTTPS、SOCKS、PAC 等代理状态。",
                    "如果不需要系统代理，关闭后重新检测；如果需要，确保 DNS 与浏览器也走同一出口。"
                ],
                actions: [
                    .copyCommand(
                        id: "copy-system-proxy-status",
                        title: "复制代理状态命令",
                        command: "scutil --proxy"
                    ),
                    .openNetwork,
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "tunnel-interface",
                title: "确认 VPN/隧道接口",
                summary: "检测到 VPN 或隧道网络接口，需要确认是否符合预期。",
                whyItMatters: "多层 VPN、隧道或代理叠加时，出口 IP、DNS、WebRTC 和时区语言更容易出现冲突。",
                category: .network,
                difficulty: .medium,
                safety: .manual,
                estimatedScoreGain: gain(["tunnel-interface"]),
                relatedImpactIDs: ["tunnel-interface"],
                steps: [
                    "确认当前是否正在使用 VPN、WireGuard、Tailscale、Clash/TUN 或类似隧道。",
                    "不需要时先关闭对应客户端，再重新检测。",
                    "需要时尽量避免多层网络叠加，并确认 DNS、WebRTC、浏览器时区与出口一致。"
                ],
                actions: [
                    .copyCommand(
                        id: "copy-interface-status",
                        title: "复制接口检查命令",
                        command: "ifconfig | grep -E '^[a-z0-9]+:|status: active|utun|tun|tap|ppp|wg'"
                    ),
                    .openVPN,
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "abuse",
                title: "避开存在滥用记录的出口",
                summary: "当前 IP 命中过近期或历史滥用信号。",
                whyItMatters: "滥用记录通常来自垃圾流量、爬虫、撞库或公开代理历史，会降低账号和请求可信度。",
                category: .identity,
                difficulty: .hard,
                safety: .manual,
                estimatedScoreGain: gain(["abuse"]),
                relatedImpactIDs: ["abuse"],
                steps: [
                    "更换出口 IP，避免使用公开共享节点。",
                    "更换后重新检测，确认滥用记录不再命中。",
                    "如果只是数据库误判，通常需要等待情报源更新。"
                ],
                actions: [
                    .copyGuide(
                        id: "copy-abuse-guide",
                        title: "复制滥用记录建议",
                        guide: "当前 IP 命中滥用记录。建议更换干净出口，避免公开共享代理池，并在更换后重新检测。"
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "webrtc",
                title: "处理 WebRTC IP 泄露",
                summary: "浏览器候选公网 IP 与出口 IP 不一致。",
                whyItMatters: "WebRTC 泄露会让网页看到代理外的真实网络路径，和出口 IP 形成冲突。",
                category: .browser,
                difficulty: .medium,
                safety: .manual,
                estimatedScoreGain: gain(["webrtc"]),
                relatedImpactIDs: ["webrtc"],
                steps: [
                    "在浏览器或代理工具里关闭 WebRTC 直连泄露。",
                    "确保代理工具覆盖 UDP/STUN 或启用 WebRTC 防泄露模式。",
                    "应用设置后重新检测 WebRTC IP 是否与出口 IP 一致。"
                ],
                actions: [
                    .copyGuide(
                        id: "copy-webrtc-guide",
                        title: "复制浏览器指南",
                        guide: """
                        WebRTC 泄露处理建议：

                        Chrome/Edge：使用可信的 WebRTC 防泄露设置或扩展，并确认代理工具覆盖 UDP/STUN。
                        Firefox：在 about:config 中评估 media.peerconnection.enabled 或 WebRTC IP handling 相关设置。
                        Safari：保持系统和浏览器更新，优先使用能接管 WebRTC 的代理/VPN 工具。

                        修改后重新运行 NetEnvCheck。
                        """
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "ipv6",
                title: "核对 IPv6 是否被代理覆盖",
                summary: "当前同时存在 IPv4 与 IPv6 出口，需要确认代理链路是否覆盖 IPv6。",
                whyItMatters: "部分代理只覆盖 IPv4，IPv6 可能绕过代理暴露另一个出口。",
                category: .network,
                difficulty: .medium,
                safety: .admin,
                estimatedScoreGain: gain(["ipv6"]),
                relatedImpactIDs: ["ipv6"],
                steps: [
                    "确认代理/VPN 客户端是否明确支持 IPv6。",
                    "如果不需要 IPv6，可在当前网络服务里临时关闭 IPv6 后复测。",
                    "关闭 IPv6 可能影响部分网络环境，执行前先记下恢复命令。"
                ],
                actions: [
                    .openNetwork,
                    .copyCommand(
                        id: "copy-list-services",
                        title: "复制网络服务列表命令",
                        command: "networksetup -listallnetworkservices"
                    ),
                    .copyCommand(
                        id: "copy-ipv6-off",
                        title: "复制关闭 Wi-Fi IPv6 命令",
                        command: "networksetup -setv6off Wi-Fi\n# 恢复：networksetup -setv6automatic Wi-Fi"
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "dns",
                title: "统一 DNS 与出口环境",
                summary: "当前 DNS 使用常见公共解析器，可能与出口 IP 归属形成不一致。",
                whyItMatters: "DNS、出口 IP 和代理链路不一致时，服务端可能看到混合环境信号。",
                category: .network,
                difficulty: .medium,
                safety: .admin,
                estimatedScoreGain: gain(["dns"]),
                relatedImpactIDs: ["dns"],
                steps: [
                    "优先使用代理/VPN 客户端提供的 DNS 或与出口地区一致的解析器。",
                    "修改 DNS 后刷新本机 DNS 缓存。",
                    "重新检测，确认 DNS 与出口环境不再明显冲突。"
                ],
                actions: [
                    .openNetwork,
                    .copyCommand(
                        id: "copy-show-dns",
                        title: "复制查看 DNS 命令",
                        command: "scutil --dns | grep 'nameserver\\[[0-9]*\\]'"
                    ),
                    .copyCommand(
                        id: "copy-flush-dns",
                        title: "复制刷新 DNS 缓存命令",
                        command: "sudo dscacheutil -flushcache\nsudo killall -HUP mDNSResponder"
                    ),
                    .copyGuide(
                        id: "copy-dns-guide",
                        title: "复制 DNS 优化指南",
                        guide: """
                        DNS 优化建议：

                        1. 优先使用代理/VPN 工具提供的 DNS。
                        2. 不要让 DNS 落在与出口 IP 明显不同的地区。
                        3. 修改 DNS 后刷新本机缓存，再重新检测。
                        4. 如果不确定网络服务名称，先运行：networksetup -listallnetworkservices
                        """
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "timezone",
                title: "统一系统和浏览器时区",
                summary: "系统或浏览器时区与 IP 归属地时区不一致。",
                whyItMatters: "时区是常见环境一致性信号，与出口地区冲突时容易被识别为跨区代理环境。",
                category: .system,
                difficulty: .easy,
                safety: .safe,
                estimatedScoreGain: gain(["system-timezone", "browser-timezone"]),
                relatedImpactIDs: ["system-timezone", "browser-timezone"],
                steps: [
                    "打开日期与时间设置，将时区调整到出口 IP 归属地附近。",
                    "确认浏览器/WebView 暴露的时区也随系统变化。",
                    "调整完成后重新检测。"
                ],
                actions: [
                    .openDateTime,
                    .copyGuide(
                        id: "copy-timezone-guide",
                        title: "复制时区指南",
                        guide: "将系统时区和浏览器时区调整为与出口 IP 归属地一致。调整后重新检测时区项。"
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "language",
                title: "统一语言、地区和 Accept-Language",
                summary: "系统语言、浏览器语言或 HTTP 语言头与 IP 归属地不一致。",
                whyItMatters: "语言地区和 Accept-Language 会被服务端用于判断环境是否自然一致。",
                category: .system,
                difficulty: .easy,
                safety: .safe,
                estimatedScoreGain: gain(["system-language", "browser-language", "http-language"]),
                relatedImpactIDs: ["system-language", "browser-language", "http-language"],
                steps: [
                    "打开语言与地区设置，将地区调整到出口 IP 归属地。",
                    "调整浏览器语言优先级，让首选语言和出口地区一致。",
                    "重新检测 HTTP Accept-Language 是否已同步。"
                ],
                actions: [
                    .openLanguageRegion,
                    .copyGuide(
                        id: "copy-language-guide",
                        title: "复制语言设置指南",
                        guide: """
                        语言一致性优化建议：

                        1. 系统“语言与地区”里的地区应与出口 IP 归属地一致。
                        2. 浏览器首选语言应与目标地区一致，例如 US 对应 en-US。
                        3. HTTP Accept-Language 通常跟随浏览器语言优先级。
                        4. 修改后重新检测系统语言、浏览器语言和 HTTP 语言头。
                        """
                    ),
                    .refresh
                ]
            )
        )

        append(
            RemediationPlan(
                id: "country-conflict",
                title: "稳定 IP 归属地情报",
                summary: "不同数据源给出的 IP 国家/地区不一致。",
                whyItMatters: "归属地冲突通常表示 IP 情报库未同步，服务端可能看到不同地区结论。",
                category: .data,
                difficulty: .hard,
                safety: .manual,
                estimatedScoreGain: gain(["country-conflict"]),
                relatedImpactIDs: ["country-conflict"],
                steps: [
                    "更换归属地更稳定的出口 IP。",
                    "如果是新分配或刚迁移的 IP，等待情报库同步。",
                    "使用多源结果交叉确认，不只看单一接口。"
                ],
                actions: [
                    .copyGuide(
                        id: "copy-country-conflict-guide",
                        title: "复制归属地冲突指南",
                        guide: "不同 IP 情报源给出的归属地不一致。建议更换归属更稳定的出口，或等待情报库更新后复测。"
                    ),
                    .refresh
                ]
            )
        )

        return plans.sorted { lhs, rhs in
            if lhs.estimatedScoreGain != rhs.estimatedScoreGain {
                return lhs.estimatedScoreGain > rhs.estimatedScoreGain
            }
            return lhs.title < rhs.title
        }
    }

    static func guide(for report: CheckReport) -> String {
        let plans = plans(for: report)
        guard !plans.isEmpty else {
            return "NetEnvCheck 未发现需要修复的扣分项。"
        }

        let body = plans.map { plan in
            """
            ## \(plan.title)
            预计可改善：+\(plan.estimatedScoreGain)
            难度：\(plan.difficulty.title)
            安全级别：\(plan.safety.title)
            原因：\(plan.summary)
            影响：\(plan.whyItMatters)
            步骤：
            \(plan.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
            """
        }.joined(separator: "\n\n")

        return """
        NetEnvCheck 修复建议
        当前评分：\(report.riskScore) / 100
        当前风险：\(report.riskBand.title)
        出口 IP：\(report.publicIP ?? "--")

        \(body)
        """
    }
}

private extension RemediationAction {
    static var refresh: RemediationAction {
        RemediationAction(
            id: "refresh",
            title: "重新检测",
            systemImage: "arrow.clockwise",
            kind: .refresh,
            safety: .safe
        )
    }

    static var openDateTime: RemediationAction {
        RemediationAction(
            id: "open-date-time",
            title: "打开日期与时间",
            systemImage: "clock",
            kind: .openSettings(.dateTime),
            safety: .safe
        )
    }

    static var openLanguageRegion: RemediationAction {
        RemediationAction(
            id: "open-language-region",
            title: "打开语言与地区",
            systemImage: "character.bubble",
            kind: .openSettings(.languageRegion),
            safety: .safe
        )
    }

    static var openNetwork: RemediationAction {
        RemediationAction(
            id: "open-network",
            title: "打开网络设置",
            systemImage: "network",
            kind: .openSettings(.network),
            safety: .safe
        )
    }

    static var openVPN: RemediationAction {
        RemediationAction(
            id: "open-vpn",
            title: "打开 VPN/网络设置",
            systemImage: "lock.shield",
            kind: .openSettings(.vpn),
            safety: .safe
        )
    }

    static func copyCommand(id: String, title: String, command: String) -> RemediationAction {
        RemediationAction(
            id: id,
            title: title,
            systemImage: "terminal",
            kind: .copyCommand(command),
            safety: .admin
        )
    }

    static func copyGuide(id: String, title: String, guide: String) -> RemediationAction {
        RemediationAction(
            id: id,
            title: title,
            systemImage: "doc.on.doc",
            kind: .copyGuide(guide),
            safety: .safe
        )
    }
}
