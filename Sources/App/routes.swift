import Fluent
import Vapor

struct OHLCDataProviderKey: StorageKey {
    typealias Value = OHLCDataProvider
}

func routes(_ app: Application) throws {
    // MARK: - Coins
    app.get("coins") { req -> EventLoopFuture<[Coin]> in
        // Check if `ids` query parameter is provided
        if let idsString = try? req.query.get(String.self, at: "ids") {
            let ids = idsString.split(separator: ",").map { String($0) }
            return Coin.query(on: req.db)
                .filter(\.$id ~~ ids)
                .sort(\.$marketCapRank, .ascending)
                .all()
        }
        
        // Default to pagination if `ids` is not provided
        let page = (try? req.query.get(Int.self, at: "page")) ?? 1
        let perPage = (try? req.query.get(Int.self, at: "per_page")) ?? 250
        
        guard page > 0, perPage > 0 else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Page and per_page must be positive integers"))
        }
        
        let lowerBound = (page - 1) * perPage
        let upperBound = lowerBound + perPage
        
        return Coin.query(on: req.db)
            .sort(\.$marketCapRank, .ascending)
            .range(lowerBound..<upperBound)
            .all()
    }
    
    app.get("search") { req -> EventLoopFuture<[Coin]> in
        guard let searchTerm = try? req.query.get(String.self, at: "query").lowercased(),
              !searchTerm.isEmpty else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Query parameter 'query' is required"))
        }
        
        return Coin.query(on: req.db)
            .group(.or) { group in
                group
                    .filter(\.$name ~~ searchTerm)
                    .filter(\.$id ~~ searchTerm)
                    .filter(\.$symbol ~~ searchTerm)
            }
            .sort(\.$marketCapRank, .ascending)
            .all()
    }
    
    app.get("market-data") { req -> EventLoopFuture<[String: MarketData]> in
        guard let idsString = try? req.query.get(String.self, at: "ids"), !idsString.isEmpty else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Query parameter 'ids' is required"))
        }
        
        let ids = idsString.split(separator: ",").map { String($0) }
        
        return Coin.query(on: req.db)
            .filter(\.$id ~~ ids)
            .all()
            .map { coins in
                var marketDataDict: [String: MarketData] = [:]
                for coin in coins {
                    let marketData = MarketData(
                        currentPrice: coin.currentPrice,
                        marketCap: coin.marketCap,
                        marketCapRank: coin.marketCapRank,
                        fullyDilutedValuation: coin.fullyDilutedValuation,
                        totalVolume: coin.totalVolume,
                        high24H: coin.high24H,
                        low24H: coin.low24H,
                        priceChange24H: coin.priceChange24H,
                        priceChangePercentage24H: coin.priceChangePercentage24H,
                        marketCapChange24H: coin.marketCapChange24H,
                        marketCapChangePercentage24H: coin.marketCapChangePercentage24H,
                        circulatingSupply: coin.circulatingSupply,
                        totalSupply: coin.totalSupply,
                        ath: coin.ath,
                        athChangePercentage: coin.athChangePercentage,
                        athDate: coin.athDate,
                        atl: coin.atl,
                        atlChangePercentage: coin.atlChangePercentage,
                        atlDate: coin.atlDate
                    )
                    marketDataDict[coin.id!] = marketData
                }
                return marketDataDict
            }
    }
    
    app.get("ohlc") { req -> EventLoopFuture<[String: [OHLCData]]> in
        guard let symbol = try? req.query.get(String.self, at: "symbol"), !symbol.isEmpty else {
            throw Abort(.badRequest, reason: "Query parameter 'symbol' is required")
        }
        
        guard let currency = try? req.query.get(Currency.self, at: "currency") else {
            throw Abort(.badRequest, reason: "Query parameter 'currency' is missing or invalid")
        }
        
        let provider: OHLCDataProvider = req.application.storage[OHLCDataProviderKey.self] ?? CoinScannerController.shared
        return provider.fetchOHLCData(symbol: symbol, currency: currency, req: req)
    }
    
    // MARK: - Global Market Data
    app.get("global-market-data") { req -> EventLoopFuture<GlobalMarketData> in
        GlobalMarketData.query(on: req.db)
            .first()
            .flatMapThrowing { globalData -> GlobalMarketData in
                guard let globalData else {
                    throw Abort(.notFound, reason: "No global market data found")
                }
                return globalData
            }
    }
    
    // MARK: - Price Alerts
    let headers = HTTPHeaders([("content-type", "application/json")])
    
    app.get("users", ":user_id", "price-alerts") { req -> EventLoopFuture<[PriceAlert]> in
        guard let userID = req.parameters.get("user_id") else {
            throw Abort(.badRequest, reason: "user_id parameter must not be empty")
        }
        
        guard let deviceToken = req.headers.first(name: "X-Device-ID") else {
            throw Abort(.badRequest, reason: "X-Device-ID header missing")
        }
        
        return PriceAlert.query(on: req.db)
            .filter(\.$userID == userID)
            .all()
            .flatMap { priceAlerts in
                let updateFutures = priceAlerts.map { priceAlert in
                    priceAlert.deviceToken = deviceToken
                    return priceAlert.update(on: req.db)
                }
                return updateFutures.flatten(on: req.eventLoop).transform(to: priceAlerts)
            }
    }
    
    app.post("users", ":user_id", "price-alert") { req -> EventLoopFuture<Response> in
        guard let userID = req.parameters.get("user_id") else {
            throw Abort(.badRequest, reason: "user_id parameter must not be empty")
        }
        
        do {
            let priceAlert = try req.content.decode(PriceAlert.self)
            
            guard let id = priceAlert.id, !id.isEmpty else {
                throw Abort(.badRequest, reason: "id parameter must not be empty")
            }
            
            guard priceAlert.targetPrice > 0 else {
                throw Abort(.badRequest, reason: "target_price must be greater than zero")
            }
            
            guard let deviceToken = req.headers.first(name: "X-Device-ID") else {
                throw Abort(.badRequest, reason: "X-Device-ID header missing")
            }
            
            priceAlert.userID = userID
            priceAlert.deviceToken = deviceToken
            
            return PriceAlert.query(on: req.db)
                .filter(\.$userID == userID)
                .filter(\.$symbol == priceAlert.symbol)
                .filter(\.$targetPrice == priceAlert.targetPrice)
                .first()
                .flatMap { existingPriceAlert in
                    if existingPriceAlert != nil {
                        return req.eventLoop.makeFailedFuture(
                            Abort(
                                .conflict,
                                reason: "Price alert already exists for this coin with the same target price"
                            )
                        )
                    } else {
                        return priceAlert.save(on: req.db).flatMapThrowing {
                            Response(
                                status: .ok,
                                headers: headers,
                                body: .init(data: try JSONEncoder().encode(priceAlert))
                            )
                        }
                    }
                }
        } catch {
            return req.eventLoop.makeFailedFuture(error)
        }
    }
    
    app.delete("users", ":user_id", "price-alert", ":id") { req -> EventLoopFuture<Response> in
        guard let userID = req.parameters.get("user_id") else {
            throw Abort(.badRequest, reason: "user_id parameter must not be empty")
        }
        
        guard let id = req.parameters.get("id") else {
            throw Abort(.badRequest, reason: "id parameter must not be empty")
        }
        
        return PriceAlert.query(on: req.db)
            .filter(\.$userID == userID)
            .filter(\.$id == id)
            .first()
            .flatMap { priceAlert -> EventLoopFuture<Response> in
                guard let priceAlert else {
                    return req.eventLoop.makeFailedFuture(
                        Abort(
                            .notFound,
                            headers: headers,
                            reason: "Could not find price alert with the following coin id: \(id) for user id: \(userID)"
                        )
                    )
                }
                
                let body: Data
                do {
                    let encoder = JSONEncoder()
                    body = try encoder.encode(priceAlert)
                } catch {
                    return req.eventLoop.makeFailedFuture(Abort(.internalServerError))
                }
                
                return priceAlert.delete(on: req.db).flatMapThrowing {
                    Response(status: .ok, headers: headers, body: .init(data: body))
                }
            }
    }
}
