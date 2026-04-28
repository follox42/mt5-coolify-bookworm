"""
FastAPI REST wrapper around mt5linux RPyC server.

Talks to a `mt5linux` server (default: mt5-ftmo:8001 via internal Coolify
network) and exposes HTTP REST endpoints for non-Python clients (curl,
Postman, JS bots, etc.).

Env vars:
    MT5_RPYC_HOST   : hostname of mt5linux server (default: mt5-ftmo)
    MT5_RPYC_PORT   : port of mt5linux server (default: 8001)

Endpoints:
    GET  /health
    GET  /account
    GET  /positions
    GET  /symbols
    GET  /symbol/{name}
    GET  /candles?symbol=EURUSD&timeframe=M1&count=100
    POST /order
        body: {"symbol":"EURUSD","type":"buy","volume":0.01,"sl":0,"tp":0}
"""

from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

MT5_HOST = os.environ.get("MT5_RPYC_HOST", "mt5-ftmo")
MT5_PORT = int(os.environ.get("MT5_RPYC_PORT", "8001"))

# Lazy-imported and shared across requests
_mt5: Any = None


def get_mt5():
    global _mt5
    if _mt5 is None:
        from mt5linux import MetaTrader5  # type: ignore
        _mt5 = MetaTrader5(host=MT5_HOST, port=MT5_PORT)
        if not _mt5.initialize():
            err = _mt5.last_error()
            _mt5 = None
            raise HTTPException(status_code=503, detail=f"MT5 initialize failed: {err}")
    return _mt5


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    if _mt5 is not None:
        try:
            _mt5.shutdown()
        except Exception:
            pass


app = FastAPI(title="MT5 REST API", lifespan=lifespan)


def _to_dict(obj: Any) -> dict:
    """Convert MT5 named tuple / namespace to dict."""
    if obj is None:
        return {}
    if hasattr(obj, "_asdict"):
        return obj._asdict()
    return dict(obj.__dict__) if hasattr(obj, "__dict__") else {"value": obj}


# ---- timeframe map ----
_TF = {
    "M1": 1, "M2": 2, "M3": 3, "M4": 4, "M5": 5, "M6": 6, "M10": 10,
    "M12": 12, "M15": 15, "M20": 20, "M30": 30,
    "H1": 16385, "H2": 16386, "H3": 16387, "H4": 16388, "H6": 16390,
    "H8": 16392, "H12": 16396,
    "D1": 16408, "W1": 32769, "MN1": 49153,
}


@app.get("/health")
def health():
    return {"status": "ok", "mt5_rpyc": f"{MT5_HOST}:{MT5_PORT}"}


@app.get("/account")
def account():
    mt5 = get_mt5()
    info = mt5.account_info()
    if info is None:
        raise HTTPException(503, "account_info() returned None")
    return _to_dict(info)


@app.get("/positions")
def positions():
    mt5 = get_mt5()
    pos = mt5.positions_get()
    if pos is None:
        return []
    return [_to_dict(p) for p in pos]


@app.get("/symbols")
def symbols():
    mt5 = get_mt5()
    syms = mt5.symbols_get()
    if syms is None:
        return []
    return [s.name for s in syms]


@app.get("/symbol/{name}")
def symbol(name: str):
    mt5 = get_mt5()
    info = mt5.symbol_info(name)
    if info is None:
        raise HTTPException(404, f"symbol {name} not found")
    tick = mt5.symbol_info_tick(name)
    return {"info": _to_dict(info), "tick": _to_dict(tick) if tick else None}


@app.get("/candles")
def candles(symbol: str, timeframe: str = "M1", count: int = 100):
    if timeframe not in _TF:
        raise HTTPException(400, f"unknown timeframe {timeframe}, valid: {list(_TF)}")
    mt5 = get_mt5()
    rates = mt5.copy_rates_from_pos(symbol, _TF[timeframe], 0, count)
    if rates is None or len(rates) == 0:
        return []
    # rates is a numpy structured array; convert each row to dict
    return [
        {
            "time": int(r["time"]),
            "open": float(r["open"]),
            "high": float(r["high"]),
            "low": float(r["low"]),
            "close": float(r["close"]),
            "tick_volume": int(r["tick_volume"]),
            "spread": int(r["spread"]),
            "real_volume": int(r["real_volume"]),
        }
        for r in rates
    ]


class OrderRequest(BaseModel):
    symbol: str
    type: str  # "buy" or "sell"
    volume: float
    sl: float = 0.0
    tp: float = 0.0
    deviation: int = 20
    magic: int = 0
    comment: str = "rest-api"


@app.post("/order")
def place_order(req: OrderRequest):
    mt5 = get_mt5()
    info = mt5.symbol_info(req.symbol)
    if info is None:
        raise HTTPException(404, f"symbol {req.symbol} not found")
    tick = mt5.symbol_info_tick(req.symbol)
    if tick is None:
        raise HTTPException(503, "no tick data — symbol may be inactive")

    order_type = mt5.ORDER_TYPE_BUY if req.type.lower() == "buy" else mt5.ORDER_TYPE_SELL
    price = tick.ask if order_type == mt5.ORDER_TYPE_BUY else tick.bid

    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": req.symbol,
        "volume": req.volume,
        "type": order_type,
        "price": price,
        "sl": req.sl,
        "tp": req.tp,
        "deviation": req.deviation,
        "magic": req.magic,
        "comment": req.comment,
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    result = mt5.order_send(request)
    if result is None:
        raise HTTPException(500, f"order_send returned None: {mt5.last_error()}")
    return _to_dict(result)
