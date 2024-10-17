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
    // Get Coins
    func testGetCoinsSuccess() async throws {
        let bitcoin = try await createBitcoin()
        let ethereum = try await createEthereum()
        try app.test(.GET, "coins") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 2)
            assertCoin(coins.first!, bitcoin)
            assertCoin(coins.last!, ethereum)
        }
    }
    
    func testGetCoinsPaginationSuccess() async throws {
        let bitcoin = try await createBitcoin()
        let ethereum = try await createEthereum()
        _ = try await createBNB()
        
        try app.test(.GET, "coins?page=1&per_page=2") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 2)
            XCTAssertEqual(coins.map { $0.coinID }, [bitcoin.coinID, ethereum.coinID])
        }
    }
    
    func testGetCoinsPaginationEmpty() async throws {
        _ = try await createBitcoin()
        try app.test(.GET, "coins?page=2&per_page=2") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertTrue(coins.isEmpty)
        }
    }
    
    func testGetCoinsInvalidPage() throws {
        try app.test(.GET, "coins?page=-1") { response in
            XCTAssertEqual(response.status, .badRequest)
        }
    }
    
    // Search Coins
    func testSearchCoinsSuccess() async throws {
        let bitcoin = try await createBitcoin()
        try app.test(.GET, "search?query=\(bitcoin.coinID)") { response in
            XCTAssertEqual(response.status, .ok)
            let coins = try response.content.decode([Coin].self)
            XCTAssertEqual(coins.count, 1)
            XCTAssertEqual(coins.first?.coinID, bitcoin.coinID)
        }
    }
    
    func testSearchCoinsEmptyQuery() throws {
        try app.test(.GET, "search?query=") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("Query parameter 'query' is required"))
        }
    }
    
    // Get Market Data
    func testGetMarketDataSuccess() async throws {
        let bitcoin = try await createBitcoin()
        try app.test(.GET, "market-data?ids=\(bitcoin.coinID)") { response in
            XCTAssertEqual(response.status, .ok)
            let marketData = try response.content.decode([String: MarketData].self)
            XCTAssertEqual(marketData[bitcoin.coinID]?.currentPrice, bitcoin.currentPrice)
            XCTAssertEqual(marketData[bitcoin.coinID]?.priceChange, bitcoin.priceChangePercentage24H)
        }
    }
    
    func testGetMarketDataMissingIDs() throws {
        try app.test(.GET, "market-data?ids=") { response in
            XCTAssertEqual(response.status, .badRequest)
            XCTAssertTrue(response.body.string.contains("Query parameter 'ids' is required"))
        }
    }
    
    func testGetMarketDataWithInvalidIDs() async throws {
        _ = try await createBitcoin()
        try app.test(.GET, "market-data?ids=nonexistentcoin") { response in
            XCTAssertEqual(response.status, .ok)
            let marketData = try response.content.decode([String: MarketData].self)
            XCTAssertTrue(marketData.isEmpty)
        }
    }
    
    // MARK: - Helpers
    private func createCoin(
        coinID: String,
        coinName: String,
        coinImage: String = "",
        marketCapRank: Int64,
        currentPrice: Double,
        priceChangePercentage24H: Double
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
    
    private func createBitcoin() async throws -> Coin {
        try await createCoin(
            coinID: "bitcoin",
            coinName: "Bitcoin",
            marketCapRank: 1,
            currentPrice: 65000,
            priceChangePercentage24H: -5
        )
    }
    
    private func createEthereum() async throws -> Coin {
        try await createCoin(
            coinID: "ethereum",
            coinName: "Ethereum",
            marketCapRank: 2,
            currentPrice: 2000,
            priceChangePercentage24H: 2
        )
    }
    
    private func createBNB() async throws -> Coin {
        try await createCoin(
            coinID: "binancecoin",
            coinName: "BNB",
            marketCapRank: 3,
            currentPrice: 600,
            priceChangePercentage24H: 10
        )
    }
    
    private func assertCoin(_ expected: Coin, _ actual: Coin) {
        XCTAssertEqual(expected.coinID, actual.coinID)
        XCTAssertEqual(expected.coinName, actual.coinName)
        XCTAssertEqual(expected.coinImage, actual.coinImage)
        XCTAssertEqual(expected.marketCapRank, actual.marketCapRank)
        XCTAssertEqual(expected.currentPrice, actual.currentPrice)
        XCTAssertEqual(expected.priceChangePercentage24H, actual.priceChangePercentage24H)
    }
}
