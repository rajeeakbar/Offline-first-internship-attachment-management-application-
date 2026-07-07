-- 1. Create Profiles Table
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT,
  role TEXT CHECK (role IN ('student', 'academic_supervisor', 'industry_supervisor', 'admin')),
  supervisor_id UUID REFERENCES public.profiles(id),
  industry_supervisor_id UUID REFERENCES public.profiles(id),
  department TEXT,
  student_id_number TEXT,
  company_name TEXT,
  status TEXT DEFAULT 'pending',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create Log Entries Table
CREATE TABLE public.log_entries (
  id UUID PRIMARY KEY,
  student_id UUID REFERENCES public.profiles(id) NOT NULL,
  supervisor_id UUID REFERENCES public.profiles(id),
  date TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  day_number INTEGER,
  work_description TEXT,
  knowledge_acquired TEXT,
  recommendation TEXT,
  status TEXT DEFAULT 'submitted',
  score INTEGER,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Create Media Attachments Table
CREATE TABLE public.media_attachments (
  id UUID PRIMARY KEY,
  log_id UUID REFERENCES public.log_entries(id) ON DELETE CASCADE,
  remote_url TEXT,
  file_type TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 4. Enable Row Level Security (RLS)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.log_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.media_attachments ENABLE ROW LEVEL SECURITY;

-- 5. Profiles RLS Policies
CREATE POLICY "Public profiles are viewable by everyone" ON public.profiles
  FOR SELECT USING (true);

CREATE POLICY "Users can insert their own profile" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

-- 6. Log Entries RLS Policies
CREATE POLICY "Students can view and create their own logs" ON public.log_entries
  FOR ALL USING (auth.uid() = student_id);

CREATE POLICY "Supervisors can view logs of their assigned students" ON public.log_entries
  FOR SELECT USING (
    auth.uid() = supervisor_id OR
    auth.uid() IN (
      SELECT supervisor_id FROM public.profiles WHERE id = log_entries.student_id
    )
  );

CREATE POLICY "Supervisors can update logs of their assigned students" ON public.log_entries
  FOR UPDATE USING (
    auth.uid() = supervisor_id
  );

-- 7. Media Attachments RLS Policies
CREATE POLICY "Access based on log entry visibility" ON public.media_attachments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.log_entries
      WHERE log_entries.id = media_attachments.log_id
    )
  );

-- 8. Storage Buckets
-- 8. Companies Table
CREATE TABLE public.companies (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  address TEXT,
  contact_person TEXT,
  email TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.companies ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Companies are viewable by authenticated users" ON public.companies
  FOR SELECT USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage companies" ON public.companies
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 9. App Settings Table
CREATE TABLE public.app_settings (
  id TEXT PRIMARY KEY,
  key TEXT UNIQUE,
  value TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Settings are viewable by everyone" ON public.app_settings
  FOR SELECT USING (true);

CREATE POLICY "Admins can manage settings" ON public.app_settings
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 10. Storage Buckets
-- Run this in the Supabase Dashboard:
-- INSERT INTO storage.buckets (id, name, public) VALUES ('logs', 'logs', true);
