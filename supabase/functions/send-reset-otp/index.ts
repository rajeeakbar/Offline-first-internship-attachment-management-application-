import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { Resend } from "https://esm.sh/resend@3.0.0";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")! // Use SERVICE ROLE for admin actions
);
const resend = new Resend(Deno.env.get("RESEND_API_KEY")!);

serve(async (req) => {
  try {
    const { email, action, otp, newPassword } = await req.json();

    if (!email) {
      return new Response(JSON.stringify({ error: "Email is required" }), { status: 400 });
    }

    // --- ACTION 1: SEND OTP ---
    if (action === "send") {
      const code = Math.floor(100000 + Math.random() * 900000).toString();

      // Delete old codes for this email
      await supabase.from("password_reset_otps").delete().eq("email", email);

      // Insert new code
      const { error: insertError } = await supabase.from("password_reset_otps").insert({
        email: email,
        otp_code: code,
        expires_at: new Date(Date.now() + 10 * 60000).toISOString(),
      });

      if (insertError) {
        return new Response(JSON.stringify({ error: "Failed to store OTP" }), { status: 500 });
      }

      // Send email via Resend
      const { error: emailError } = await resend.emails.send({
        from: "noreply@resend.dev", // Using Resend's testing domain by default
        to: email,
        subject: "Your Password Reset Code",
        html: `<p>Your password reset code is: <strong>${code}</strong></p>
               <p>This code expires in 10 minutes.</p>`,
      });

      if (emailError) {
        console.error("Email Error:", emailError);
        return new Response(JSON.stringify({ error: "Failed to send email" }), { status: 500 });
      }

      return new Response(JSON.stringify({ success: true }), { status: 200 });
    }

    // --- ACTION 2: VERIFY OTP & RESET PASSWORD ---
    if (action === "reset") {
      if (!otp || !newPassword) {
        return new Response(JSON.stringify({ error: "OTP and new password are required" }), { status: 400 });
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
        return new Response(JSON.stringify({ error: "Invalid or expired code" }), { status: 400 });
      }

      // Mark code as used
      await supabase.from("password_reset_otps").update({ used: true }).eq("id", data.id);

      // Get the user ID from Supabase Auth
      const { data: userData, error: userError } = await supabase.auth.admin.getUserByEmail(email);
      if (userError || !userData || !userData.user) {
        return new Response(JSON.stringify({ error: "User not found" }), { status: 404 });
      }

      // Update the password using Admin API
      const { error: updateError } = await supabase.auth.admin.updateUserById(
        userData.user.id,
        { password: newPassword }
      );

      if (updateError) {
        return new Response(JSON.stringify({ error: updateError.message }), { status: 500 });
      }

      return new Response(JSON.stringify({ success: true }), { status: 200 });
    }

    return new Response(JSON.stringify({ error: "Invalid action" }), { status: 400 });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
