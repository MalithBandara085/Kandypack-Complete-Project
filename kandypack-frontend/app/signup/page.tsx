"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";

interface City {
  cityId: string;
  cityName: string;
}

export default function Signup() {
  const [customerName, setCustomerName] = useState("");
  const [deliveryAddress, setDeliveryAddress] = useState("");
  const [phoneNumber, setPhoneNumber] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [cityId, setCityId] = useState("");
  const [cities, setCities] = useState<City[]>([]);
  const [message, setMessage] = useState("");
  const router = useRouter();

  useEffect(() => {
    setCities([
      { cityId: "CMB", cityName: "Colombo" },
      { cityId: "NEG", cityName: "Negombo" },
      { cityId: "GAL", cityName: "Galle" },
      { cityId: "MAT", cityName: "Matara" },
      { cityId: "JAF", cityName: "Jaffna" },
      { cityId: "TRN", cityName: "Trincomalee" },
    ]);
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("Creating account...");

    try {
      const response = await fetch("http://localhost:8081/api/auth/signup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          customerName,
          deliveryAddress,
          phoneNumber,
          email,
          password,
          cityId,
        }),
      });

      const data = await response.json();

      if (response.ok) {
        localStorage.setItem("token", data.token);
        localStorage.setItem("customerId", data.customerId);
        localStorage.setItem("role", data.role);
        setMessage("Account created! Redirecting...");
        router.push("/");
      } else {
        setMessage("Signup failed: " + (data.message || JSON.stringify(data)));
      }
    } catch (err: unknown) {
      setMessage("Request failed: " + (err instanceof Error ? err.message : "Please try again."));
    }
  };

  return (
    <div className="auth-shell">
      <div className="auth-panel">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-slate-800">Create Account</h1>
          <p className="text-sm text-slate-500 mt-1">
            Sign up to start placing orders
          </p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-4">
          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              Full Name
            </label>
            <input
              type="text"
              value={customerName}
              onChange={(e) => setCustomerName(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              Delivery Address
            </label>
            <input
              type="text"
              value={deliveryAddress}
              onChange={(e) => setDeliveryAddress(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              City
            </label>
            <select
              value={cityId}
              onChange={(e) => setCityId(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            >
              <option value="">Select a city</option>
              {cities.map((c) => (
                <option key={c.cityId} value={c.cityId}>
                  {c.cityName}
                </option>
              ))}
            </select>
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              Phone Number
            </label>
            <input
              type="text"
              value={phoneNumber}
              onChange={(e) => setPhoneNumber(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-slate-700 mb-1.5">
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              className="w-full border border-slate-300 rounded-lg px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-[#1e3a5f] focus:border-transparent transition"
            />
          </div>

          <button
            type="submit"
            className="bg-[#1e3a5f] text-white font-medium rounded-lg px-4 py-2.5 mt-2 hover:bg-[#2c5282] transition"
          >
            Sign Up
          </button>
        </form>

        {message && (
          <div
            className={`mt-5 text-sm text-center px-4 py-2.5 rounded-lg ${
              message.toLowerCase().includes("failed") ||
              message.toLowerCase().includes("error")
                ? "bg-red-50 text-red-700"
                : message.toLowerCase().includes("created")
                ? "bg-green-50 text-green-700"
                : "bg-slate-50 text-slate-600"
            }`}
          >
            {message}
          </div>
        )}
      </div>
    </div>
  );
}