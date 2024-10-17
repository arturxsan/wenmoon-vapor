import APNS

struct PriceAlertNotification: APNSwiftNotification {
    let coinID: String
    let aps: APNSwiftPayload
    
    init(coinID: String, aps: APNSwiftPayload) {
        self.coinID = coinID
        self.aps = aps
    }
}
