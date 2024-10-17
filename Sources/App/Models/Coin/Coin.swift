import Fluent
import Vapor

final class Coin: Model, Content {
    static let schema = "coins"
    
    @ID(key: .id)
    var id: UUID?
    
    @Field(key: "coin_id")
    var coinID: String
    
    @Field(key: "coin_name")
    var coinName: String
    
    @Field(key: "coin_image")
    var coinImage: String
    
    @Field(key: "market_cap_rank")
    var marketCapRank: Int64?
    
    @Field(key: "current_price")
    var currentPrice: Double?
    
    @Field(key: "price_change_percentage_24h")
    var priceChangePercentage24H: Double?
    
    init() { }
    
    init(
        id: UUID? = nil,
        coinID: String,
        coinName: String,
        coinImage: String,
        marketCapRank: Int64?,
        currentPrice: Double?,
        priceChangePercentage24H: Double?
    ) {
        self.id = id
        self.coinID = coinID
        self.coinName = coinName
        self.coinImage = coinImage
        self.marketCapRank = marketCapRank
        self.currentPrice = currentPrice
        self.priceChangePercentage24H = priceChangePercentage24H
    }
    
    private enum CodingKeys: String, CodingKey {
        case id, name, image, large, marketCapRank, currentPrice, priceChangePercentage24H
    }
    
    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let coinID = try container.decode(String.self, forKey: .id)
        let coinName = try container.decode(String.self, forKey: .name)
        let coinImage = try container.decode(String.self, forKey: .image)
        let marketCapRank = try container.decodeIfPresent(Int64.self, forKey: .marketCapRank)
        let currentPrice = try container.decodeIfPresent(Double.self, forKey: .currentPrice)
        let priceChangePercentage24H = try container.decodeIfPresent(Double.self, forKey: .priceChangePercentage24H)
        self.init(
            coinID: coinID,
            coinName: coinName,
            coinImage: coinImage,
            marketCapRank: marketCapRank,
            currentPrice: currentPrice,
            priceChangePercentage24H: priceChangePercentage24H
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(coinID, forKey: .id)
        try container.encode(coinName, forKey: .name)
        try container.encode(coinImage, forKey: .image)
        try container.encode(marketCapRank, forKey: .marketCapRank)
        try container.encode(currentPrice, forKey: .currentPrice)
        try container.encode(priceChangePercentage24H, forKey: .priceChangePercentage24H)
    }
}
