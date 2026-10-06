"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function Login() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [message, setMessage] = useState("");
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setMessage("Logging in...");

    try {
      const response = await fetch("http://localhost:8081/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email, password }),
      });

      const data = await response.json();

      if (response.ok) {
        localStorage.setItem("token", data.token);
        localStorage.setItem("customerId", data.customerId || data.staffId);
        localStorage.setItem("role", data.role);
        setMessage("Login successful! Redirecting...");

        if (data.role === "CUSTOMER") {
          router.push("/");
        } else {
          router.push("/dashboard");
        }
      } else {
        setMessage("Login failed: " + (data.message || data));
      }
    } catch (err: unknown) {
      setMessage("Request failed: " + (err instanceof Error ? err.message : "Please try again."));
    }
  };

  return (
    <div className="auth-shell">
      <div className="auth-panel">
        <div className="mb-6 text-center">
          <h1 className="text-2xl font-bold text-slate-800">Kandypack</h1>
          <p className="text-sm text-slate-500 mt-1">
            Sign in to your account
          </p>
        </div>

        <form onSubmit={handleSubmit} className="flex flex-col gap-5">
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
            Log In
          </button>
        </form>

        {message && (
          <div
            className={`mt-5 text-sm text-center px-4 py-2.5 rounded-lg ${
              message.toLowerCase().includes("failed") ||
              message.toLowerCase().includes("error")
                ? "bg-red-50 text-red-700"
                : message.toLowerCase().includes("success")
                ? "bg-green-50 text-green-700"
                : "bg-slate-50 text-slate-600"
            }`}
          >
            {message}
          </div>
        )}

        <p className="mt-5 text-sm text-center text-slate-500">
          Don&apos;t have an account?{" "}
          <a href="/signup" className="font-medium text-[#1e3a5f] hover:underline">
            Sign up
          </a>
        </p>
      </div>
    </div>
  );
}