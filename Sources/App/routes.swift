import Fluent
import Vapor

func routes(_ app: Application) throws {
    // MARK: - Coins
    app.get("coins") { req -> EventLoopFuture<[Coin]> in
        let page = (try? req.query.get(Int.self, at: "page")) ?? 1
        let perPage = (try? req.query.get(Int.self, at: "per_page")) ?? 250
        
        guard page > 0, perPage > 0 else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Page and per_page must be positive integers."))
        }
        
        let lowerBound = (page - 1) * perPage
        let upperBound = lowerBound + perPage
        
        return Coin.query(on: req.db)
            .sort(\.$marketCapRank, .ascending)
            .range(lowerBound..<upperBound)
            .all()
    }
    
    app.get("search") { req -> EventLoopFuture<[Coin]> in
        guard let searchTerm = try? req.query.get(String.self, at: "query"), !searchTerm.isEmpty else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Query parameter 'query' is required"))
        }
        
        return Coin.query(on: req.db)
            .group(.or) { group in
                group
                    .filter(\.$coinName ~~ searchTerm)
                    .filter(\.$coinID ~~ searchTerm)
            }
            .sort(\.$marketCapRank, .ascending)
            .all()
    }
    
    app.get("market-data") { req -> EventLoopFuture<[String: MarketData]> in
        guard let coinIDsString = try? req.query.get(String.self, at: "ids"), !coinIDsString.isEmpty else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Query parameter 'ids' is required"))
        }
        
        let coinIDs = coinIDsString.split(separator: ",").map { String($0) }
        
        return Coin.query(on: req.db)
            .filter(\.$coinID ~~ coinIDs)
            .all()
            .map { coins in
                var marketDataDict: [String: MarketData] = [:]
                for coin in coins {
                    let marketData = MarketData(currentPrice: coin.currentPrice, priceChange: coin.priceChangePercentage24H)
                    marketDataDict[coin.coinID] = marketData
                }
                return marketDataDict
            }
    }
    
    // MARK: - Price Alerts
    app.get("price-alerts") { req -> EventLoopFuture<[PriceAlert]> in
        guard let deviceToken = req.headers.first(name: "X-Device-ID") else {
            return PriceAlert.query(on: req.db).all()
        }
        return PriceAlert.query(on: req.db)
            .filter(\.$deviceToken == deviceToken)
            .all()
    }
    
    app.post("price-alert") { req -> EventLoopFuture<Response> in
        do {
            let priceAlert = try req.content.decode(PriceAlert.self)
            
            guard !priceAlert.coinID.isEmpty else {
                throw Abort(.badRequest, reason: "coin_id parameter must not be empty")
            }
            
            guard priceAlert.targetPrice > 0 else {
                throw Abort(.badRequest, reason: "target_price must be greater than zero")
            }
            
            guard let deviceToken = req.headers.first(name: "X-Device-ID") else {
                throw Abort(.badRequest, reason: "X-Device-ID header missing")
            }
            
            priceAlert.deviceToken = deviceToken
            
            return PriceAlert.query(on: req.db)
                .filter(\.$deviceToken == deviceToken)
                .filter(\.$coinID == priceAlert.coinID)
                .first()
                .flatMap { existingPriceAlert in
                    if existingPriceAlert != nil {
                        return req.eventLoop.makeFailedFuture(Abort(.conflict, reason: "Price alert already exists for this coin and device."))
                    } else {
                        return priceAlert.save(on: req.db).flatMapThrowing {
                            let headers = HTTPHeaders([("content-type", "application/json")])
                            return Response(status: .ok, headers: headers, body: .init(data: try JSONEncoder().encode(priceAlert)))
                        }
                    }
                }
        } catch {
            return req.eventLoop.makeFailedFuture(error)
        }
    }
    
    app.delete("price-alert", ":coin_id") { req -> EventLoopFuture<Response> in
        guard let coinID = req.parameters.get("coin_id") else {
            throw Abort(.badRequest)
        }
        
        guard let deviceToken = req.headers.first(name: "X-Device-ID") else {
            throw Abort(.badRequest, reason: "X-Device-ID header missing")
        }
        
        return PriceAlert.query(on: req.db)
            .filter(\.$deviceToken == deviceToken)
            .filter(\.$coinID == coinID)
            .first()
            .flatMap { priceAlert -> EventLoopFuture<Response> in
                let headers = HTTPHeaders([("content-type", "application/json")])
                guard let priceAlert else {
                    return req.eventLoop.makeFailedFuture(Abort(.notFound,
                                                                headers: headers,
                                                                reason: "Could not find price alert with the following coin id: \(coinID)"))
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
