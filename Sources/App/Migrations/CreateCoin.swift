import Fluent

struct CreateCoin: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("coins")
            .id()
            .field("coin_id", .string, .required)
            .field("coin_name", .string, .required)
            .field("coin_image", .string, .required)
            .field("market_cap_rank", .int64)
            .field("current_price", .double)
            .field("price_change_percentage_24h", .double)
            .create()
    }
    
    func revert(on database: Database) async throws {
        try await database.schema("coins").delete()
    }
}
