-- 1. Create Profiles Table (if not exists)
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  full_name TEXT,
  role TEXT CHECK (role IN ('student', 'academic_supervisor', 'industry_supervisor', 'admin')),
  supervisor_id UUID REFERENCES public.profiles(id),
  department TEXT,
  student_id_number TEXT,
  company_name TEXT,
  status TEXT DEFAULT 'pending',
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create Log Entries Table (if not exists)
CREATE TABLE IF NOT EXISTS public.log_entries (
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

-- 3. Create Media Attachments Table (if not exists)
CREATE TABLE IF NOT EXISTS public.media_attachments (
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

-- 5. DROP old trigger first (to avoid conflicts)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- 6. Create the NEW trigger function (FIXED - no UPDATE on auth.users)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, role, status, updated_at)
  VALUES (
    NEW.id,
    NEW.raw_user_meta_data->>'full_name',
    COALESCE(NEW.raw_user_meta_data->>'role', 'student'),
    'pending',
    NOW()
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Create the trigger (AFTER INSERT)
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 8. RLS Policies for profiles
DROP POLICY IF EXISTS "Enable insert for authenticated users" ON public.profiles;
CREATE POLICY "Enable insert for authenticated users"
ON public.profiles
FOR INSERT
WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
ON public.profiles
FOR SELECT
USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
ON public.profiles
FOR UPDATE
USING (auth.uid() = id);

-- 9. Log Entries RLS Policies
DROP POLICY IF EXISTS "Students can view and create their own logs" ON public.log_entries;
CREATE POLICY "Students can view and create their own logs" ON public.log_entries
  FOR ALL USING (auth.uid() = student_id);

DROP POLICY IF EXISTS "Supervisors can view logs of their assigned students" ON public.log_entries;
CREATE POLICY "Supervisors can view logs of their assigned students" ON public.log_entries
  FOR SELECT USING (
    auth.uid() = supervisor_id OR
    auth.uid() IN (
      SELECT supervisor_id FROM public.profiles WHERE id = log_entries.student_id
    )
  );

DROP POLICY IF EXISTS "Supervisors can update logs of their assigned students" ON public.log_entries;
CREATE POLICY "Supervisors can update logs of their assigned students" ON public.log_entries
  FOR UPDATE USING (
    auth.uid() = supervisor_id
  );

-- 10. Media Attachments RLS Policies
DROP POLICY IF EXISTS "Access based on log entry visibility" ON public.media_attachments;
CREATE POLICY "Access based on log entry visibility" ON public.media_attachments
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM public.log_entries
      WHERE log_entries.id = media_attachments.log_id
    )
  );