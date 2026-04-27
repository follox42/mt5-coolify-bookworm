"""FastAPI wrapper around mt5linux RPyC server.

Runs on Linux Python and talks to the Wine-side mt5linux server on localhost:18812.
The Wine-side server has the official MetaTrader5 Python lib bound to the
running terminal64.exe.

Auth: optional X-API-Key header (set API_KEY env var to enable).
"""
from __future__ import annotations
import os
from typing import Optional, Any

from fastapi import FastAPI, HTTPException, Header
from pydantic import BaseModel

try:
    from mt5linux import MetaTrader5
except Exception as e:
    MetaTrader5 = None
    print(f"[FATAL] mt5linux import error: {e}")

MT5_HOST = os.environ.get("MT5_RPYC_HOST", "localhost")
MT5_PORT = int(os.environ.get("MT5_RPYC_PORT", "18812"))
API_KEY = os.environ.get("API_KEY", "")

app = FastAPI(title="MT5 Bookworm API", version="0.1")

_mt5: Optional[Any] = None


def _auth(x_api_key: Optional[str]) -> None:
    if not API_KEY:
        return
    if x_api_key != API_KEY:
        raise HTTPException(401, "bad x-api-key")


def _client():
    global _mt5
    if MetaTrader5 is None:
        raise HTTPException(500, "mt5linux not installed in Linux python")
    if _mt5 is None:
        _mt5 = MetaTrader5(host=MT5_HOST, port=MT5_PORT)
        ok = _mt5.initialize()
        if not ok:
            raise HTTPException(503, f"mt5 init failed: {_mt5.last_error()}")
    return _mt5


@app.get("/")
def root():
    return {"service": "mt5-bookworm", "status": "up"}


@app.get("/health")
def health(x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    try:
        m = _client()
        ti = m.terminal_info()
        ai = m.account_info()
        return {
            "ok": True,
            "connected": bool(ti and getattr(ti, "connected", False)),
            "broker": getattr(ai, "company", None),
            "login": getattr(ai, "login", None),
            "currency": getattr(ai, "currency", None),
            "version": list(m.version() or []),
        }
    except HTTPException:
        raise
    except Exception as e:
        return {"ok": False, "error": str(e)}


@app.get("/account")
def account(x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    a = _client().account_info()
    if a is None:
        raise HTTPException(503, "no account_info")
    return {
        "login": a.login,
        "balance": a.balance,
        "equity": a.equity,
        "margin": a.margin,
        "margin_free": a.margin_free,
        "profit": a.profit,
        "leverage": a.leverage,
        "currency": a.currency,
        "company": a.company,
        "name": a.name,
    }


@app.get("/positions")
def positions(x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    m = _client()
    pos = m.positions_get() or []
    return [
        {
            "ticket": p.ticket,
            "symbol": p.symbol,
            "type": "buy" if p.type == 0 else "sell",
            "volume": p.volume,
            "price_open": p.price_open,
            "sl": p.sl,
            "tp": p.tp,
            "profit": p.profit,
            "time": p.time,
            "magic": p.magic,
        }
        for p in pos
    ]


@app.get("/symbols")
def symbols(limit: int = 200, x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    m = _client()
    s = m.symbols_get() or []
    return [{"name": x.name, "description": getattr(x, "description", "")} for x in s[:limit]]


@app.get("/symbol/{name}")
def symbol(name: str, x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    m = _client()
    info = m.symbol_info(name)
    if info is None:
        raise HTTPException(404, f"symbol {name} not found")
    return {
        "name": info.name,
        "bid": info.bid,
        "ask": info.ask,
        "spread": info.spread,
        "digits": info.digits,
        "point": info.point,
        "trade_mode": info.trade_mode,
    }


class CandlesReq(BaseModel):
    symbol: str
    timeframe: str = "M15"  # M1 M5 M15 M30 H1 H4 D1
    count: int = 200


@app.post("/history/candles")
def candles(body: CandlesReq, x_api_key: Optional[str] = Header(None)):
    _auth(x_api_key)
    m = _client()
    tf_map = {
        "M1": m.TIMEFRAME_M1, "M5": m.TIMEFRAME_M5, "M15": m.TIMEFRAME_M15,
        "M30": m.TIMEFRAME_M30, "H1": m.TIMEFRAME_H1, "H4": m.TIMEFRAME_H4,
        "D1": m.TIMEFRAME_D1, "W1": m.TIMEFRAME_W1, "MN1": m.TIMEFRAME_MN1,
    }
    tf = tf_map.get(body.timeframe.upper())
    if tf is None:
        raise HTTPException(400, f"timeframe {body.timeframe} unsupported")
    rates = m.copy_rates_from_pos(body.symbol, tf, 0, body.count)
    if rates is None:
        raise HTTPException(503, f"copy_rates failed: {m.last_error()}")
    return [
        {
            "time": int(r["time"]),
            "open": float(r["open"]),
            "high": float(r["high"]),
            "low": float(r["low"]),
            "close": float(r["close"]),
            "tick_volume": int(r["tick_volume"]),
        }
        for r in rates
    ]


class FlatBody(BaseModel):
    magic: Optional[int] = None
    symbol: Optional[str] = None


@app.post("/flat")
def flat(body: FlatBody, x_api_key: Optional[str] = Header(None)):
    """Panic close — closes all positions matching magic and/or symbol filter."""
    _auth(x_api_key)
    m = _client()
    pos = m.positions_get() or []
    closed = []
    for p in pos:
        if body.magic is not None and p.magic != body.magic:
            continue
        if body.symbol is not None and p.symbol != body.symbol:
            continue
        req = {
            "action": m.TRADE_ACTION_DEAL,
            "position": p.ticket,
            "symbol": p.symbol,
            "volume": p.volume,
            "type": m.ORDER_TYPE_SELL if p.type == 0 else m.ORDER_TYPE_BUY,
            "deviation": 20,
            "magic": p.magic,
            "type_time": m.ORDER_TIME_GTC,
            "type_filling": m.ORDER_FILLING_IOC,
        }
        result = m.order_send(req)
        closed.append({"ticket": p.ticket, "retcode": getattr(result, "retcode", None)})
    return {"closed": closed, "count": len(closed)}
