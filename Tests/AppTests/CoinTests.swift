@testable import App
import Fluent
import XCTVapor

final class CoinTests: XCTestCase {
    // MARK: - Properties
    var app: Application!

    // MARK: - Setup
    override func setUp() async throws {
        app = try await Application.testable()
    }

    override func tearDown() async throws {
        try await app.autoRevert()
        try await app.asyncShutdown()
    }

    // MARK: - Tests

    // Basic Functionality Tests
    func testGetAllCoinsSuccess() async throws {
        let coin1 = try await createCoin()
        let coin2 = try await createCoin(coinID: "ethereum")

        try app.test(.GET, "coins") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 2)
            XCTAssertEqual(coins.first?.coinID, coin1.coinID)
            XCTAssertEqual(coins.last?.coinID, coin2.coinID)
        }
    }

    func testGetCoinsPaginationSuccess() async throws {
        let coin1 = try await createCoin()
        let coin2 = try await createCoin(coinID: "ethereum")
        _ = try await createCoin(coinID: "litecoin")

        try app.test(.GET, "coins?page=1&per_page=2") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 2)
            XCTAssertEqual(coins.map { $0.coinID }, [coin1.coinID, coin2.coinID])
        }
    }

    func testGetCoinsPaginationEmpty() async throws {
        _ = try await createCoin()
        try app.test(.GET, "coins?page=2&per_page=2") { response in
            XCTAssertEqual(response.status, .ok)
            
            let coins = try response.content.decode([Coin].self)
            XCTAssertTrue(coins.isEmpty)
        }
    }

    // Validation Tests
    func testGetCoinsInvalidPage() throws {
        try app.test(.GET, "coins?page=-1") { response in
            XCTAssertEqual(response.status, .badRequest)
        }
    }

    func testSearchCoinsEmptyQuery() throws {
        try app.test(.GET, "search?query=") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("Query parameter 'query' is required"))
        }
    }

    // Search Functionality Tests
    func testSearchCoinsSuccess() async throws {
        let coin = try await createCoin()

        try app.test(.GET, "search?query=\(coin.coinID)") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 1)
            XCTAssertEqual(coins.first?.coinID, coin.coinID)
        }
    }

    // Market Data Tests
    func testMarketDataSuccess() async throws {
        let coin = try await createCoin()

        try app.test(.GET, "market-data?ids=\(coin.coinID)") { response in
            XCTAssertEqual(response.status, .ok)
            let marketData = try response.content.decode([String: MarketData].self)
            XCTAssertEqual(marketData[coin.coinID]?.currentPrice, coin.currentPrice)
            XCTAssertEqual(marketData[coin.coinID]?.priceChange, coin.priceChangePercentage24H)
        }
    }

    func testMarketDataMissingIDs() throws {
        try app.test(.GET, "market-data?ids=") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("Query parameter 'ids' is required"))
        }
    }

    func testMarketDataWithInvalidIDs() async throws {
        _ = try await createCoin()

        try app.test(.GET, "market-data?ids=nonexistentcoin") { response in
            XCTAssertEqual(response.status, .ok)
            let marketData = try response.content.decode([String: MarketData].self)
            XCTAssertTrue(marketData.isEmpty)
        }
    }
    
    func testResponseStructure() async throws {
        _ = try await createCoin()

        try app.test(.GET, "coins") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)

            XCTAssertEqual(coins.count, 1)
            let returnedCoin = coins.first!

            XCTAssertNotNil(returnedCoin.coinID)
            XCTAssertNotNil(returnedCoin.coinName)
            XCTAssertNotNil(returnedCoin.coinImage)
            XCTAssertNotNil(returnedCoin.marketCapRank)
            XCTAssertNotNil(returnedCoin.currentPrice)
            XCTAssertNotNil(returnedCoin.priceChangePercentage24H)
        }
    }

    // MARK: - Helpers
    private func createCoin(
        coinID: String = "bitcoin",
        coinName: String = "Bitcoin",
        coinImage: String = "",
        marketCapRank: Int64 = 1,
        currentPrice: Double = 65000,
        priceChangePercentage24H: Double = -5
    ) async throws -> Coin {
        let coin = Coin(
            coinID: coinID,
            coinName: coinName,
            coinImage: coinImage,
            marketCapRank: marketCapRank,
            currentPrice: currentPrice,
            priceChangePercentage24H: priceChangePercentage24H
        )
        try await coin.save(on: app.db)
        return coin
    }
}
