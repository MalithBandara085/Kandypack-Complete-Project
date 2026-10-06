"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

interface Order {
  orderId: string;
  customerId: string;
  customerName: string;
  amount: number;
  placementDate: string;
  deliveryDate: string;
  status: string;
}

const API = process.env.NEXT_PUBLIC_API_URL || "http://localhost:8081";

const statusColors: Record<string, string> = {
  placed: "bg-blue-50 text-blue-700",
  scheduled: "bg-amber-50 text-amber-700",
  dispatched: "bg-purple-50 text-purple-700",
  delivered: "bg-green-50 text-green-700",
  cancelled: "bg-red-50 text-red-700",
};

export default function Dashboard() {
  const [search, setSearch] = useState("");
  const [filter, setFilter] = useState("all");
  const [pending, setPending] = useState<string | null>(null);
  const [orders, setOrders] = useState<Order[]>([]);
  const [role, setRole] = useState("");
  const [message, setMessage] = useState("Loading orders...");
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("token");
    const storedRole = localStorage.getItem("role");

    if (!token) {
      router.push("/login");
      return;
    }

    if (storedRole === "CUSTOMER") {
      router.push("/");
      return;
    }

    setRole(storedRole || "");
    setFilter(storedRole === "DISPATCHER" ? "active" : "all");
    loadOrders(token);
  }, [router]);

  const loadOrders = (token: string) => {
    fetch(`${API}/api/orders`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then(async (res) => { const data = await res.json(); if (!res.ok) throw new Error(data.message || "Could not load orders"); if (!Array.isArray(data)) throw new Error("Unexpected order response"); return data; })
      .then((data: Order[]) => {
        setOrders([...data].sort((a, b) => b.placementDate.localeCompare(a.placementDate) || a.orderId.localeCompare(b.orderId)));
        setMessage(data.length === 0 ? "No orders found." : "");
      })
      .catch((err) => setMessage("Failed to load orders: " + (err instanceof Error ? err.message : "Please try again.")));
  };

  const handleExport = async () => {
    const token = localStorage.getItem("token");
    setMessage("Requesting export...");

    try {
      const response = await fetch(
        `${API}/api/orders/export/csv`,
        {
          headers: { Authorization: `Bearer ${token}` },
        }
      );

      if (!response.ok) {
        const text = await response.text();
        setMessage(`Export failed (${response.status}): ${text}`);
        return;
      }

      const blob = await response.blob();
      const url = window.URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "orders_report.csv";
      document.body.appendChild(a);
      a.click();
      a.remove();
      window.URL.revokeObjectURL(url);
      setMessage("Export downloaded successfully.");
    } catch (err: unknown) {
      setMessage("Export failed with exception: " + (err instanceof Error ? err.message : "Please try again."));
    }
  };

  const updateStatus = async (orderId: string, newStatus: string) => {
    const token = localStorage.getItem("token");
    if (pending) return;
    setPending(orderId);
    setMessage(`Updating ${orderId}...`);

    try {
      const response = await fetch(
        `${API}/api/orders/${orderId}/status`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${token}`,
          },
          body: JSON.stringify({ status: newStatus }),
        }
      );

      const data = await response.json();

      if (response.ok) {
        setMessage(`Order ${orderId} updated to ${newStatus}`);
        setOrders(current => current.map(order => order.orderId === orderId ? {...order, status: newStatus} : order));
      } else {
        setMessage("Error: " + (data.message || JSON.stringify(data)));
      }
    } catch (err: unknown) {
      setMessage("Request failed: " + (err instanceof Error ? err.message : "Please try again."));
    } finally { setPending(null); }
  };

  const isDispatcher = role === "DISPATCHER";
  const activeStatuses = ["placed", "scheduled", "dispatched"];
  const visibleOrders = orders.filter(o => (filter === "all" || (filter === "active" ? activeStatuses.includes(o.status) : o.status === filter)) && `${o.orderId} ${o.customerName}`.toLowerCase().includes(search.toLowerCase())).sort((a, b) => isDispatcher ? a.deliveryDate.localeCompare(b.deliveryDate) || a.orderId.localeCompare(b.orderId) : b.placementDate.localeCompare(a.placementDate) || a.orderId.localeCompare(b.orderId));
  const cards: [string, number, string][] = isDispatcher
    ? [["Active deliveries", orders.filter(o => activeStatuses.includes(o.status)).length, "active"], ["Awaiting scheduling", orders.filter(o => o.status === "placed").length, "placed"], ["Ready for dispatch", orders.filter(o => o.status === "scheduled").length, "scheduled"], ["On the way", orders.filter(o => o.status === "dispatched").length, "dispatched"]]
    : [["All orders", orders.length, "all"], ["Active orders", orders.filter(o => activeStatuses.includes(o.status)).length, "active"], ["Delivered", orders.filter(o => o.status === "delivered").length, "delivered"], ["Cancelled", orders.filter(o => o.status === "cancelled").length, "cancelled"]];
  return (
    <div className="workspace-shell">
      <div className="workspace-panel">
        <div className="section-heading">
          <div>
            <h1 className="text-2xl font-bold text-slate-800">
              {isDispatcher ? "Dispatch centre" : role === "ADMIN" ? "Administration overview" : "Staff orders"}
            </h1>
            <p className="text-sm text-slate-500 mt-1">
              {isDispatcher ? "Plan the next delivery. Active orders are listed by earliest delivery date." : "Monitor orders, review fulfilment and export your order report."}
            </p>
          </div>
          {["ADMIN", "DISPATCHER"].includes(role) && <button
            onClick={handleExport}
            className="bg-slate-100 text-slate-700 text-sm font-medium rounded-lg px-4 py-2 hover:bg-slate-200 transition"
          >
            Download Report (CSV)
          </button>}
        </div>

        <div className="stats-grid">{cards.map(([label, value, status]) => <button type="button" style={{textAlign:"left", borderColor: filter === status ? "#c64d1e" : undefined}} className="stat-card" key={label} aria-pressed={filter === status} onClick={() => setFilter(status)}><span>{label}</span><strong>{value}</strong></button>)}</div>
        {!isDispatcher && role === "ADMIN" && <p className="mb-5 text-sm text-slate-600">Delivered order value: <strong>Rs. {orders.filter(o => o.status === "delivered").reduce((sum, o) => sum + Number(o.amount), 0).toLocaleString("en-LK", {minimumFractionDigits: 2, maximumFractionDigits: 2})}</strong> · CSV includes all orders, regardless of the current filter.</p>}
        <div className="table-tools"><input aria-label="Search orders" type="search" placeholder="Search order ID or customer" value={search} onChange={e => setSearch(e.target.value)} /><select aria-label="Filter order status" value={filter} onChange={e => setFilter(e.target.value)}>{["all", "active", "placed", "scheduled", "dispatched", "delivered", "cancelled"].map(s => <option value={s} key={s}>{s === "all" ? "All statuses" : s === "active" ? "Active orders" : s}</option>)}</select></div>
        {message && (
          <p role="status" className="notice">{message}</p>
        )}

        <p className="mb-4 text-xs text-slate-500">Showing {visibleOrders.length} of {orders.length} orders. {isDispatcher ? "CSV exports all orders. Completed orders remain available through the status filter." : "Newest placement dates first."}</p>
        {orders.length > 0 && visibleOrders.length === 0 && <p className="empty-state">No orders match your search and status filter.</p>}
        {visibleOrders.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left">
              <thead>
                <tr className="border-b border-slate-200 text-slate-500">
                  <th className="py-3 font-medium">Order ID</th>
                  <th className="py-3 font-medium">Customer</th>
                  <th className="py-3 font-medium">Amount</th>
                  <th className="py-3 font-medium">Delivery</th>
                  <th className="py-3 font-medium">Status</th>
                  <th className="py-3 font-medium">Update</th>
                </tr>
              </thead>
              <tbody>
                {visibleOrders.map((o) => (
                  <tr
                    key={o.orderId}
                    className="border-b border-slate-100 hover:bg-slate-50 transition"
                  >
                    <td className="py-3 font-medium text-slate-700">
                      {o.orderId}
                    </td>
                    <td className="py-3 text-slate-600">{o.customerName}</td>
                    <td className="py-3 text-slate-600">Rs. {o.amount}</td>
                    <td className="py-3 text-slate-600">{o.deliveryDate}</td>
                    <td className="py-3">
                      <span
                        className={`px-2.5 py-1 rounded-full text-xs font-medium capitalize ${
                          statusColors[o.status] || "bg-slate-100 text-slate-600"
                        }`}
                      >
                        {o.status}
                      </span>
                    </td>
                    <td className="py-3">
                      <select
                        aria-label={`Change status for ${o.orderId}`}
                        disabled={pending !== null || !["ADMIN", "DISPATCHER", "DRIVER"].includes(role) || o.status === "delivered" || o.status === "cancelled"}
                        defaultValue=""
                        onChange={(e) => {
                          if (e.target.value) {
                            updateStatus(o.orderId, e.target.value);
                            e.target.value = "";
                          }
                        }}
                        className="border border-slate-300 rounded-lg px-2 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-[#1e3a5f]"
                      >
                        <option value="">Change status...</option>
                        {(o.status === "placed" ? ["scheduled", "cancelled"] :
                          o.status === "scheduled" ? ["dispatched", "cancelled"] :
                          o.status === "dispatched" ? ["delivered"] : []).map((s) => (
                          <option key={s} value={s}>
                            {s}
                          </option>
                        ))}
                      </select>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}