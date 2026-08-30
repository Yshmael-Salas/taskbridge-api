-- src/service.sql
-- Project service functions: create, update status, get by team, delete

-- 1) Create a project and return the created row
CREATE OR REPLACE FUNCTION create_project(
  p_name TEXT,
  p_description TEXT DEFAULT NULL,
  p_team_id UUID DEFAULT NULL,
  p_status project_status DEFAULT 'planned'
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  description TEXT,
  team_id UUID,
  status project_status,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
DECLARE
  new_id UUID;
BEGIN
  INSERT INTO projects (name, description, team_id, status)
  VALUES (p_name, p_description, p_team_id, p_status)
  RETURNING id INTO new_id;

  RETURN QUERY SELECT id, name, description, team_id, status, created_at, updated_at
               FROM projects
               WHERE id = new_id;
END;
$$ LANGUAGE plpgsql;

-- 2) Update project status, return the updated project row
CREATE OR REPLACE FUNCTION update_project_status(
  p_id UUID,
  p_status project_status
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  description TEXT,
  team_id UUID,
  status project_status,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  UPDATE projects
  SET status = p_status
  WHERE id = p_id
  RETURNING id, name, description, team_id, status, created_at, updated_at;
END;
$$ LANGUAGE plpgsql;

-- 3) Get projects by team (returns multiple rows)
CREATE OR REPLACE FUNCTION get_projects_by_team(
  p_team_id UUID
)
RETURNS SETOF projects AS $$
  SELECT *
  FROM projects
  WHERE team_id = p_team_id
  ORDER BY created_at DESC;
$$ LANGUAGE sql;

-- 4) Delete a project by id; return boolean indicating success
CREATE OR REPLACE FUNCTION delete_project(
  p_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  deleted_id UUID;
BEGIN
  DELETE FROM projects
  WHERE id = p_id
  RETURNING id INTO deleted_id;

  RETURN deleted_id IS NOT NULL;
END;
$$ LANGUAGE plpgsql;

-- Optional helper: move project between teams (atomic)
CREATE OR REPLACE FUNCTION move_project_to_team(
  p_project_id UUID,
  p_new_team_id UUID
)
RETURNS TABLE(
  id UUID,
  name TEXT,
  description TEXT,
  team_id UUID,
  status project_status,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  UPDATE projects
  SET team_id = p_new_team_id
  WHERE id = p_project_id
  RETURNING id, name, description, team_id, status, created_at, updated_at;
END;
$$ LANGUAGE plpgsql;
