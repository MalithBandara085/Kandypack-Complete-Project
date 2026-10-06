"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

interface Order {
  orderId: string;
  amount: number;
  placementDate: string;
  deliveryDate: string;
  status: string;
  allocations?: { tripId: string; productId: string; productName: string; quantity: number; arrival: string; active: boolean }[];
}

const statusColors: Record<string, string> = {
  placed: "bg-blue-50 text-blue-700",
  scheduled: "bg-amber-50 text-amber-700",
  dispatched: "bg-purple-50 text-purple-700",
  delivered: "bg-green-50 text-green-700",
  cancelled: "bg-red-50 text-red-700",
};

export default function OrderHistory() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [message, setMessage] = useState("Loading orders...");
  const router = useRouter();

  useEffect(() => {
    const token = localStorage.getItem("token");

    if (!token) {
      router.push("/login");
      return;
    }

    fetch(`${process.env.NEXT_PUBLIC_API_URL || "http://localhost:8081"}/api/orders/my`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then(async (res) => {
        const text = await res.text();
        let data;
        try { data = JSON.parse(text); } catch { throw new Error(text || "Invalid response"); }
        if (!res.ok) throw new Error(data.message || "Could not load orders");
        return data;
      })
      .then((data: Order[]) => {
        setOrders([...data].sort((a, b) => b.placementDate.localeCompare(a.placementDate) || a.orderId.localeCompare(b.orderId)));
        setMessage(data.length === 0 ? "No orders found." : "");
      })
      .catch((err) => setMessage("Failed to load orders: " + (err instanceof Error ? err.message : "Please try again.")));
  }, [router]);

  return (
    <div className="workspace-shell">
      <div className="workspace-panel">
        <div className="mb-6">
          <h1 className="text-2xl font-bold text-slate-800">Order History</h1>
          <p className="text-sm text-slate-500 mt-1">
            A record of all orders placed.
          </p>
        </div>

        {message && (
          <p className="text-sm text-slate-500 py-8 text-center">{message}</p>
        )}

        {orders.length > 0 && (
          <div className="overflow-x-auto">
            <table className="w-full text-sm text-left">
              <thead>
                <tr className="border-b border-slate-200 text-slate-500">
                  <th className="py-3 font-medium">Order ID</th>
                  <th className="py-3 font-medium">Amount</th>
                  <th className="py-3 font-medium">Placed</th>
                  <th className="py-3 font-medium">Delivery</th>
                  <th className="py-3 font-medium">Status</th>
                </tr>
              </thead>
              <tbody>
                {orders.map((o) => (
                  <tr
                    key={o.orderId}
                    className="border-b border-slate-100 hover:bg-slate-50 transition"
                  >
                    <td className="py-3 font-medium text-slate-700">
                      {o.orderId}
                      {o.allocations && o.allocations.length > 0 && <details className="mt-2 text-xs font-normal">
                        <summary className="cursor-pointer text-blue-800">Train allocations</summary>
                        <ul className="mt-2 space-y-2">{o.allocations.map(a => <li key={`${a.tripId}-${a.productId}`}>
                          {a.quantity} x {a.productName} on {a.tripId}<br />
                          Arrival: {a.arrival.replace("T", " ")} (Sri Lanka time)
                          {!a.active && <span className="block text-red-700">Reservation released</span>}
                        </li>)}</ul>
                      </details>}
                    </td>
                    <td className="py-3 text-slate-600">Rs. {o.amount}</td>
                    <td className="py-3 text-slate-600">{o.placementDate}</td>
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