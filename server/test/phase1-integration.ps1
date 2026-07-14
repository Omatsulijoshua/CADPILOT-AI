param([string]$BaseUrl = 'http://127.0.0.1:3000/v1')
$ErrorActionPreference = 'Stop'
$email = 'integration+' + [guid]::NewGuid().ToString('N') + '@cadpilot.test'
$auth = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/register" -ContentType 'application/json' -Body (@{ email=$email; password='TestPass123!'; displayName='Integration Designer' } | ConvertTo-Json)
$headers = @{ Authorization = "Bearer $($auth.accessToken)" }
$blocked = $false
try { Invoke-RestMethod -Method Get -Uri "$BaseUrl/projects" | Out-Null } catch { $blocked = $_.Exception.Response.StatusCode.value__ -eq 401 }
if (-not $blocked) { throw 'Unauthenticated project access was not rejected.' }
$project = Invoke-RestMethod -Method Post -Uri "$BaseUrl/projects" -Headers $headers -ContentType 'application/json' -Body (@{name='Integration Bracket'} | ConvertTo-Json)
$syncBody = @{ mutationId=[guid]::NewGuid().ToString(); baseRevision=1; payload=@{formatVersion=1;operations=@()} } | ConvertTo-Json -Depth 5
$sync = Invoke-RestMethod -Method Post -Uri "$BaseUrl/projects/$($project.id)/sync" -Headers $headers -ContentType 'application/json' -Body $syncBody
$repeat = Invoke-RestMethod -Method Post -Uri "$BaseUrl/projects/$($project.id)/sync" -Headers $headers -ContentType 'application/json' -Body $syncBody
if ($sync.status -ne 'APPLIED' -or $repeat.id -ne $sync.id) { throw 'Idempotent sync failed.' }
$rotated = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/refresh" -ContentType 'application/json' -Body (@{refreshToken=$auth.refreshToken} | ConvertTo-Json)
$oldRejected = $false
try { Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/refresh" -ContentType 'application/json' -Body (@{refreshToken=$auth.refreshToken} | ConvertTo-Json) | Out-Null } catch { $oldRejected = $_.Exception.Response.StatusCode.value__ -eq 401 }
if (-not $oldRejected) { throw 'Refresh token rotation failed.' }
$logout = Invoke-RestMethod -Method Post -Uri "$BaseUrl/auth/logout" -ContentType 'application/json' -Body (@{refreshToken=$rotated.refreshToken} | ConvertTo-Json)
if (-not $logout.success) { throw 'Logout failed.' }
Write-Output 'Phase 1 API integration checks passed.'
