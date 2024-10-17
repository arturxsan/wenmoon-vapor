import Fluent
import Vapor

final class PriceAlert: Model, Content {
    static let schema = "price_alerts"
    
    enum TargetDirection: String, Codable {
        case above = "ABOVE"
        case below = "BELOW"
    }
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "coin_id")
    var coinID: String
    
    @Field(key: "coin_name")
    var coinName: String
    
    @Field(key: "target_price")
    var targetPrice: Double
    
    @Field(key: "target_direction")
    var targetDirection: TargetDirection
    
    @Field(key: "device_token")
    var deviceToken: String?
    
    init() { }
    
    init(
        id: UUID? = nil,
        coinID: String,
        coinName: String,
        targetPrice: Double,
        targetDirection: TargetDirection,
        deviceToken: String? = nil
    ) {
        self.id = id
        self.coinID = coinID
        self.coinName = coinName
        self.targetPrice = targetPrice
        self.targetDirection = targetDirection
        self.deviceToken = deviceToken
    }
    
    private enum CodingKeys: String, CodingKey {
        case coinID = "coin_id"
        case coinName = "coin_name"
        case targetPrice = "target_price"
        case targetDirection = "target_direction"
        case deviceToken = "device_token"
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coinID = try container.decode(String.self, forKey: .coinID)
        let coinName = try container.decode(String.self, forKey: .coinName)
        let targetPrice = try container.decode(Double.self, forKey: .targetPrice)
        let targetDirection = try container.decode(TargetDirection.self, forKey: .targetDirection)
        let deviceToken = try container.decodeIfPresent(String.self, forKey: .deviceToken)
        self.init(
            coinID: coinID,
            coinName: coinName,
            targetPrice: targetPrice,
            targetDirection: targetDirection,
            deviceToken: deviceToken
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coinID, forKey: .coinID)
        try container.encode(coinName, forKey: .coinName)
        try container.encode(targetPrice, forKey: .targetPrice)
        try container.encode(targetDirection, forKey: .targetDirection)
        try container.encode(deviceToken, forKey: .deviceToken)
    }
}
