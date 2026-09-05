param(
  [Parameter(Mandatory=$true)][ValidatePattern('^[a-z][a-z0-9_]*_test$')][string]$Database,
  [int]$Port = 55439,
  [string]$User = 'diurna_test',
  [string]$Psql = 'psql'
)
$ErrorActionPreference = 'Stop'
if ($Port -eq 5432) { throw 'Use an isolated test cluster on a non-default port.' }
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$arguments = @('-h','127.0.0.1','-p',"$Port",'-U',$User,'-d',$Database,'-v','ON_ERROR_STOP=1')
$actual = & $Psql @arguments -At -c 'select current_database()'
if ($LASTEXITCODE -ne 0 -or $actual.Trim() -ne $Database) { throw 'Test database identity check failed.' }
foreach ($relative in @('supabase/tests/bootstrap.sql','supabase/schema.sql','supabase/tests/protocol_v2.sql')) {
  & $Psql @arguments -f (Join-Path $repo $relative)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $relative" }
}
