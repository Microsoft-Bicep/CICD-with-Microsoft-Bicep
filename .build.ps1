[CmdletBinding()]
Param (
    [Parameter(Mandatory = $False, HelpMessage='Specify the source directory to retrieve modules')]
    [string]$TemplatePath = "$BuildRoot\src",
    [Parameter(Mandatory = $False, HelpMessage='Specify the output directory to build ARM template')]
    [string]$BuildDirectory = "$BuildRoot\build",
    [Parameter(Mandatory = $False, HelpMessage='Specify the output directory to test ARM template')]
    [string]$TestDirectory = "$BuildRoot\testResults",
    [Parameter(Mandatory = $False, HelpMessage='Specify the resource group to publish and deploy')]
    [string]$ResourceGroupName,
    [Parameter(Mandatory = $False, HelpMessage='Specify the location of the rescoure group')]
    [string]$Location,
    $ExcludeFolders = ''
)

task Clean {
    Remove-Item -Path $BuildDirectory -Force -ErrorAction SilentlyContinue -Recurse
}

task BuildBicep {
    $Templates = (Get-ChildItem -Path $TemplatePath -Recurse -Include *.bicep) 

    foreach ($Template in $Templates) {
        Write-Build Yellow "Building bicep: $($Template.FullName)"
        if (-not (Test-Path $BuildDirectory)) {
            New-Item -Path $BuildDirectory -ItemType Directory -Force
        }
        az bicep build --file $Template.FullName --outdir $BuildDirectory
        $PackagePath = "$BuildDirectory\$($Template.Name.Replace('.bicep', '.json'))".ToString()
        $script:PackageLocation += $PackagePath
       Write-Build Yellow "Output: $PackagePath"
    }
}

task ValidateBicep {

    Uninstall-AzureRm
    if (-not (Test-Path $TestDirectory))
    {
        New-Item -Path $TestDirectory -ItemType Directory -Force
    }
    Write-Build Yellow "Retrieving test files in $TemplatePath"
    $Tests = (Get-ChildItem -Path $TemplatePath -Recurse -Include *.tests.bicep)

    $OutputPath = Join-Path -Path $TestDirectory -ChildPath TestResults.xml
    Write-Build Yellow "Output test results in $OutputPath"
    Write-Build Yellow 'Testing Az rules'

    $Params = @{
        InputPath    = $Tests
        Outcome      = 'Pass', 'Error', 'Fail'
        Format       = 'File'
        OutputFormat = 'NUnit3'
        OutputPath   = $OutputPath
    }
    Invoke-PSRule @Params -As Detail
    
    if (Test-Path $OutputPath)
    {
        [xml]$TestResults = Get-Content $OutputPath

        if ($TestResults.'test-results'.failures -gt 0 -or $TestResults.'test-results'.errors -gt 0)
        {
            Throw "Found $($TestResults.'test-results'.failures) failures and $($TestResults.'test-results'.errors) errors when executing Az rules"
        }
    }
    else
    {
        Write-Warning 'No test results outputed'
    }

    if ($env:TF_Build)
    {
        Write-Host "##vso[task.setvariable variable=PSRuleResultFile]$OutputPath"
    }
}

task TestBicep {

    if (-not (Get-Command buildHelpers -ErrorAction SilentlyContinue))
    {
        Write-Build Yellow "Importing build helper module"
        Import-Module "$BuildRoot\buildHelpers\buildHelpers.psm1"
    }

    if (-not (Test-Path $TestDirectory)) {
        New-Item -Path $TestDirectory -ItemType Directory -Force
    }

    $Packages = (Get-ChildItem -Path $BuildDirectory -Filter *.json | Where-Object {$_.Name -like "module.*"}).FullName
    $ModulePath = Get-ChildItem -Path $TestDirectory -Filter arm-ttk.psm1 -Recurse 
    Write-Build Yellow "Module Path $ModulePath"
    
    if (-not $ModulePath) {
        Write-Build Yellow "ARM Test Toolkit was not found, downloading... "
        $ARMTTKUrl = 'https://azurequickstartsservice.blob.core.windows.net/ttk/latest/arm-template-toolkit.zip'
        $DestinationDirectory = $TestDirectory + (Split-Path -Path $ARMTTKUrl -Leaf)
        try {
            Write-Build Yellow "Downloading to: $DestinationDirectory"
            Invoke-RestMethod -Uri $ARMTTKUrl -OutFile $DestinationDirectory
        }
        catch {
            Throw "Exception occured: $_"
        }

        Write-Build Yellow "Extracting ARM Test Toolkit to: $TestDirectory"
        Expand-Archive -Path $DestinationDirectory -DestinationPath $TestDirectory
        $ModulePath = (Get-ChildItem -Path $TestDirectory -Filter arm-ttk.psm1 -Recurse).FullName
    }
    Import-Module "$TestDirectory\arm-ttk\$ModulePath"
    #Import-Module $ModulePath
    foreach ($Package in $Packages){
    Write-Build Yellow "Testing against: $Package"

    $Result = Test-AzTemplate -TemplatePath $Package -Skip "Variables-Must-Be-Referenced", "Template-Should-Not-Contain-Blanks" # Both variables are used and blanks cannot be handled with nested templates
    $FileOutput = Export-NUnitXml -TestResults $Result -Path $TestDirectory
    Write-Build Yellow "NUnit reported generated: $FileOutput"
        if ($env:TF_Build){
            Write-Host "##vso[task.setvariable variable=TestResultFile]$FileOutput"
        }
    }
}

task IntegrationTest {
    if (-not (Get-AzContext))
    {
        Throw "Use Connect-AzAccount before running integration test"
    }

    Write-Build Yellow "Running integration test in $TemplatePath"

    $Configuration = New-PesterConfiguration
    $Container = New-PesterContainer -Path (Get-ChildItem $TemplatePath -Recurse -Include "*.Tests.ps1").FullName
    $Configuration.Run.Container = $Container
    $Configuration.Output.Verbosity = 'Detailed'
    $Configuration.Filter.Tag = 'Integration'
    $Configuration.Should.ErrorAction = 'Stop'
    $Configuration.TestResult.Enabled = $true
    $Configuration.TestResult.OutputFormat = 'NunitXml'
    $Configuration.TestResult.OutputPath = Join-Path -Path $TestDirectory -ChildPath 'IntegrationResults.xml'
    $Configuration.Run.PassThru = $true
    $TestResult = Invoke-Pester -Configuration $Configuration
    if ($TestResult.Failed.Count -gt 0)
    {
        Throw "One or more Pester tests failed."
    }

    if ($env:TF_Build)
    {
        $OutputFile = Join-Path -Path $TestDirectory -ChildPath 'IntegrationResults.xml'
        Write-Host "##vso[task.setvariable variable=IntegrationResultFile]$OutputFile"
    }
}

task PublishBicep {
    $Script:Templates = [System.Collections.ArrayList]@()
    $Packages = (Get-ChildItem -Path $BuildDirectory -Filter *.json | Where-Object {$_.Name -like "module.*"}).FullName
    Write-Build Yellow "Retrieved number of packages to publish: $($Packages.Count)"
    foreach ($Package in $Packages) {
        Write-Build Yellow "Retrieving content from: $Package"
        $JSONContent = Get-Content $Package | ConvertFrom-Json
        if ($JSONContent.variables.templateSpecName) {
            $TemplateObject = [PSCustomObject]@{
                TemplateFileName = $Package
                TemplateSpecName = $JSONContent.variables.templateSpecName
                Version          = $JSONContent.variables.version
                Description      = $JSONContent.variables.releasenotes
            }
            Write-Build Yellow $TemplateObject
            $null = $Templates.Add($TemplateObject)
        }
    }
    $Templates | Foreach-Object {
        $_
        Write-Host $_
        $TemplateSpecName = $_.TemplateSpecName
        try {
            $Params = @{
                ResourceGroupName = $ResourceGroupName
                Name = $TemplateSpecName
                ErrorAction = 'Stop'
            }
            $ExistingSpec = Get-AzTemplateSpec @Params
            $CurrentVersion = $ExistingSpec.Versions | Sort-Object name | Select-Object -Last 1 -ExpandProperty Name
        } catch {
            Write-Build Yellow "No version exist for template: $TemplateSpecName"
        }

        if ($_.Version -gt $CurrentVersion) {
            Write-Build Yellow "Template version is newer than in Azure, deploying..."
            try {
                $SpecParameters = @{
                    Name                = $TemplateSpecName
                    ResourceGroupName   = $ResourceGroupName
                    Location            = $Location
                    TemplateFile        = $_.TemplateFileName
                    Version             = $_.Version
                    VersionDescription  = $_.Description         
                }
                $null = New-AzTemplateSpec @SpecParameters

                Write-Build Yellow "Setting new version number"
                $Version = $_.Version
            } catch {
                $Version = $CurrentVersion
                Write-Error "Something went wrong with deploying $TemplateSpecName : $_"
            }
        } else {
            Write-Build Yellow "$TemplateSpecName template is up to date"
            Write-Build Yellow "Keeping current version number"
            $Version = $CurrentVersion
        }

        if ($env:TF_Build)
        {
            Write-Host "##vso[build.updatebuildnumber]$Version"
        }
    }
}