$env:DB_PASSWORD = Get-Secret -Name DbHubPassword -AsPlainText
try {
    claude
}
finally {
    Remove-Item Env:DB_PASSWORD -ErrorAction SilentlyContinue
}