import Foundation

/// entitlements 的 key → 中文说明。
/// 没收录的 key 直接显示原标识符，不会报错。
enum EntitlementNames {

    static func cn(_ key: String) -> String? {
        table[key]
    }

    static func display(_ key: String) -> String {
        if let cn = table[key] { return cn }
        // 前缀匹配兜底
        for (k, v) in table where key.hasPrefix(k + ".") {
            return v
        }
        return key
    }

    static let table: [String: String] = [
        // 基础
        "application-identifier": "应用标识",
        "com.apple.developer.team-identifier": "开发团队标识",
        "keychain-access-groups": "钥匙串访问组",
        "get-task-allow": "允许调试",
        "aps-environment": "推送环境",
        "beta-reports-active": "TestFlight 上报",

        // App 分组 / iCloud
        "com.apple.security.application-groups": "App 分组（共享数据）",
        "com.apple.developer.ubiquity-kvstore-identifier": "iCloud 键值存储",
        "com.apple.developer.ubiquity-container-identifiers": "iCloud 容器",
        "com.apple.developer.icloud-container-identifiers": "iCloud 容器标识",
        "com.apple.developer.icloud-services": "iCloud 服务",

        // 账号 / 登录
        "com.apple.developer.applesignin": "通过 Apple 登录",
        "com.apple.developer.associated-domains": "关联域名（通用链接）",
        "com.apple.developer.authentication-services.autofill-credential-provider": "自动填充凭据",
        "com.apple.developer.pass-type-identifiers": "钱包卡券类型",

        // 网络
        "com.apple.developer.networking.networkextension": "网络扩展（VPN / 代理 / 内容过滤）",
        "com.apple.developer.networking.vpn.api": "VPN 接口",
        "com.apple.developer.networking.wifi-info": "读取 Wi-Fi 信息",
        "com.apple.developer.networking.HotspotConfiguration": "配置热点",
        "com.apple.developer.networking.multipath": "多路径网络",
        "com.apple.developer.networking.wifi-aware": "Wi-Fi Aware 感知",
        "com.apple.developer.networking.slicing.appcategory": "应用类别网络切片",
        "com.apple.developer.networking.slicing.trafficcategory": "流量类别网络切片",
        "com.apple.external-accessory.wireless-configuration": "外部配件无线配置",
        "com.apple.developer.coremedia.hls.low-latency": "低延迟 HLS",

        // 硬件 / 传感器
        "com.apple.developer.nfc.readersession.formats": "NFC 读卡",
        "com.apple.developer.avfoundation.multitasking-camera-access": "多任务相机访问",
        "com.apple.developer.homekit": "家庭（HomeKit）",
        "com.apple.developer.healthkit": "健康（HealthKit）",
        "com.apple.developer.healthkit.access": "健康数据访问",
        "com.apple.developer.healthkit.background-delivery": "健康后台传输",
        "com.apple.developer.healthkit.recalibrate-estimates": "健康估算重校准",
        "com.apple.developer.siri": "Siri",

        // 内核 / 内存
        "com.apple.developer.kernel.increased-memory-limit": "提高内存上限",
        "com.apple.developer.kernel.increased-debugging-memory-limit": "提高调试内存上限",
        "com.apple.developer.kernel.extended-virtual-addressing": "扩展虚拟寻址",

        // 系统集成
        "com.apple.developer.system-extension.install": "安装系统扩展",
        "com.apple.developer.usernotifications.communication": "通信通知",
        "com.apple.developer.usernotifications.time-sensitive": "时效性通知",
        "com.apple.developer.user-fonts": "用户字体",
        "com.apple.developer.weatherkit": "天气（WeatherKit）",
        "com.apple.developer.game-center": "游戏中心（Game Center）",
        "com.apple.developer.devicecheck.appattest-environment": "设备验证 / App Attest",
        "com.apple.developer.ClassKit-environment": "ClassKit 教育",
        "com.apple.developer.in-app-payments": "App 内支付",
        "com.apple.developer.payment-pass-provisioning": "支付卡券配置",
        "com.apple.developer.proximity-reader.identity.display": "近距离读卡显示",
        "com.apple.developer.maps": "地图",
        "com.apple.developer.push-to-talk": "对讲推送",
                "com.apple.developer.carplay-audio": "CarPlay 音频",
        "com.apple.developer.carplay-communication": "CarPlay 通话",
        "com.apple.developer.carplay-maps": "CarPlay 地图",
        "com.apple.developer.carplay-parking": "CarPlay 停车",
        "com.apple.developer.carplay-charging": "CarPlay 充电",
        "com.apple.developer.carplay-quick-ordering": "CarPlay 快速点单",
        "inter-app-audio": "跨 App 音频",
        "com.apple.developer.fileprovider.testing-mode": "文件提供者测试模式",
        "com.apple.developer.embedded-web-browser": "内嵌浏览器",
        "com.apple.developer.thread-network": "Thread 网络",
        "com.apple.developer.matter": "Matter 智能家居",
        "com.apple.developer.accessory-transport-security": "配件传输安全",
    ]
}
