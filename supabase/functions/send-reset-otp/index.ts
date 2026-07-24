import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// Use non-reserved variable names
const supabase = createClient(
  Deno.env.get("PROJECT_URL") ?? "",
  Deno.env.get("SERVICE_ROLE_KEY") ?? ""
);

serve(async (req) => {
  try {
    // Handle CORS
    if (req.method === "OPTIONS") {
      return new Response("ok", {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization",
        },
      });
    }

    // Only accept POST requests
    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({ error: "Method not allowed" }),
        { status: 405, headers: { "Content-Type": "application/json" } }
      );
    }

    const { email, action, otp, newPassword } = await req.json();

    if (!email) {
      return new Response(
        JSON.stringify({ error: "Email is required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // --- ACTION: SEND OTP ---
    if (action === "send") {
      // Generate 6-digit OTP
      const code = Math.floor(100000 + Math.random() * 900000).toString();

      // Delete old codes for this email
      await supabase
        .from("password_reset_otps")
        .delete()
        .eq("email", email);

      // Insert new code
      const { error: insertError } = await supabase
        .from("password_reset_otps")
        .insert({
          email: email,
          otp_code: code,
          expires_at: new Date(Date.now() + 10 * 60000).toISOString(),
        });

      if (insertError) {
        console.error("Insert error:", insertError);
        return new Response(
          JSON.stringify({ error: "Failed to store OTP" }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      // Return success with OTP (for development)
      return new Response(
        JSON.stringify({
          success: true,
          message: "OTP sent successfully",
          dev_otp: code // Remove in production
        }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // --- ACTION: VERIFY OTP & RESET PASSWORD ---
    if (action === "reset") {
      if (!otp || !newPassword) {
        return new Response(
          JSON.stringify({ error: "OTP and new password are required" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Validate password strength
      if (newPassword.length < 6) {
        return new Response(
          JSON.stringify({ error: "Password must be at least 6 characters" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Fetch the valid code
      const { data, error } = await supabase
        .from("password_reset_otps")
        .select("*")
        .eq("email", email)
        .eq("otp_code", otp)
        .eq("used", false)
        .gt("expires_at", new Date().toISOString())
        .single();

      if (error || !data) {
        return new Response(
          JSON.stringify({ error: "Invalid or expired code" }),
          { status: 400, headers: { "Content-Type": "application/json" } }
        );
      }

      // Mark code as used
      await supabase
        .from("password_reset_otps")
        .update({ used: true })
        .eq("id", data.id);

      // Get user by email
      const { data: userData, error: userError } = await supabase
        .auth
        .admin
        .listUsers();

      if (userError) {
        console.error("User list error:", userError);
        return new Response(
          JSON.stringify({ error: "Failed to find user" }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      const user = userData.users.find((u: any) => u.email === email);

      if (!user) {
        return new Response(
          JSON.stringify({ error: "User not found" }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        );
      }

      // Update the password
      const { error: updateError } = await supabase
        .auth
        .admin
        .updateUserById(
          user.id,
          { password: newPassword }
        );

      if (updateError) {
        console.error("Update error:", updateError);
        return new Response(
          JSON.stringify({ error: updateError.message }),
          { status: 500, headers: { "Content-Type": "application/json" } }
        );
      }

      // Delete used OTP
      await supabase
        .from("password_reset_otps")
        .delete()
        .eq("id", data.id);

      return new Response(
        JSON.stringify({ success: true, message: "Password reset successfully" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    return new Response(
      JSON.stringify({ error: "Invalid action. Use 'send' or 'reset'" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );

  } catch (err) {
    console.error("Function error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : "Internal server error" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
