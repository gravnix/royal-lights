-- Timeline notes / reminders (תזכורות) shown on the dashboard calendar.
-- Shared across all users: any authenticated user reads and writes every note.
-- The dashboard alerts on a note the day before its date and on the date itself,
-- so no "done"/"dismissed" column is needed — alerts age out on their own.

CREATE TABLE IF NOT EXISTS public.timeline_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  note_date date NOT NULL,
  title text NOT NULL DEFAULT '',
  body text,
  created_by text,
  updated_by text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS timeline_notes_note_date_idx
  ON public.timeline_notes (note_date);

ALTER TABLE public.timeline_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated users full access" ON public.timeline_notes;
CREATE POLICY "Authenticated users full access"
  ON public.timeline_notes
  FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
