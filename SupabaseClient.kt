#!/usr/bin/env kotlin
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest
// import io.github.jan.supabase.auth.Auth // If using Auth

object SupabaseClient {
    val client = createSupabaseClient(
        supabaseUrl = BuildConfig.SUPABASE_URL,
        supabaseKey = BuildConfig.SUPABASE_ANON_KEY
    ) {
        install(Postgrest)
        // install(Auth) // Uncomment if using Auth
    }
}

