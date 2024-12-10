import Vapor
import Fluent

final class GlobalMarketData: Model, Content {
    static let schema = "global_market_data"
    
    @ID(key: .id)
    var id: UUID?

    @Field(key: "market_cap_percentage")
    var marketCapPercentage: [String: Double]

    init() { }

    init(id: UUID? = nil, marketCapPercentage: [String: Double]) {
        self.id = id
        self.marketCapPercentage = marketCapPercentage
    }
}
