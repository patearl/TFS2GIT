# Script that copies the history of an entire Team Foundati::on Server repository to a Git repository.
# Author: Wilbert van Dolleweerd
#
# Assumptions:
# - MSysgit is installed and in the PATH 
# - Team Foundation commandline tooling is installed and in the PATH (tf.exe)

Param
(
	[Parameter(Mandatory = $True)]
	[string]$TFSRepository,
	[string]$GitRepository = "ConvertedFromTFS",
	[string]$WorkspaceName = "TFS2GIT"
)

function GetTemporaryDirectory
{
	return $env:temp + "\workspace"
}

function PrepareWorkspace
{
	$TempDir = GetTemporaryDirectory

	# Remove the temporary directory if it already exists.
	if (Test-Path $TempDir)
	{
		remove-item -path $TempDir -force -recurse		
	}
	
	md $TempDir | Out-null

	# Create the workspace and map it to the temporary directory we just created.
	tf workspace /delete $WorkspaceName /noprompt
	tf workspace /new /noprompt /comment:"Temporary workspace for converting a TFS repository to Git" $WorkspaceName
	tf workfold /unmap /workspace:$WorkspaceName $/
	tf workfold /map /workspace:$WorkspaceName $TFSRepository $TempDir

	# We need this so the .git directory is hidden and will not be removed.
	git config --global core.hidedotfiles true
}


# Retrieve the history from Team Foundation Server and use a regular expression to retrieve
# the individual changeset.
function GetChangesetsFromHistory 
{
	$HistoryFileName = "history.txt"

	tf history $TFSRepository /recursive /noprompt /format:brief | Out-File $HistoryFileName

	$History = Get-Content $HistoryFileName
	[array]$ChangeSets = [regex]::Matches($History, "\d{1,5}(?=\s{5}BC2SC)")

	# Sort them from low to high.
	$ChangeSets = $ChangeSets | Sort-Object			 

	return $ChangeSets			 
}

# Actual converting takes place here.
function Convert ([array]$ChangeSets)
{
	$TemporaryDirectory = GetTemporaryDirectory

	# Initialize a new git repository.
	Write-Host "Creating empty Git repository at", $TemporaryDirectory
	git init $TemporaryDirectory

	foreach ($ChangeSet in $ChangeSets)
	{
		# Delete any leftover directories 
		Get-Childitem -path $TemporaryDirectory -Recurse | Remove-Item -force -Recurse

		# Retrieve sources from TFS
		Write-Host "Retrieving sources from", $TFSRepository, "in", $TemporaryDirectory
		Write-Host "This is changeset", $ChangeSet
		tf get $TemporaryDirectory /overwrite /force /recursive /noprompt /version:C$ChangeSet | Out-Null

		# Add sources to Git
		Write-Host "Adding sources to Git repository"
		pushd $TemporaryDirectory
		git add . | Out-Null
		$CommitMessageFileName = "commitmessage.txt"
		GetCommitMessage $ChangeSet $CommitMessageFileName
		git commit -a --file $CommitMessageFileName | Out-Null
		popd 
	}
}

# Retrieve the commit message for a specific changeset
function GetCommitMessage ([string]$ChangeSet, [string]$CommitMessageFileName)
{	
	tf changeset $ChangeSet /noprompt | Out-File $CommitMessageFileName -encoding utf8
}

# Clone the repository to the directory where you started the script.
function CloneToLocalBareRepository
{
	$TemporaryDirectory = GetTemporaryDirectory

	# If for some reason, old clone already exists, we remove it.
	if (Test-Path $GitRepository)
	{
		remove-item -path $GitRepository -force -recurse		
	}
	git clone --bare $TemporaryDirectory $GitRepository
	$(Get-Item -force $GitRepository).Attributes = "Normal"
	Write-Host "Your converted (bare) repository can be found in the" $GitRepository "directory."
}

# Clean up leftover directories and files.
function CleanUp
{
	$TempDir = GetTemporaryDirectory

	Write-Host "Removing workspace"
	tf workspace /delete $WorkspaceName /noprompt

	Write-Host "Removing working directories in" $TempDir
	Remove-Item -path $TempDir -force -recurse

	# Remove history file
	Remove-Item "history.txt"
}

function Main
{
	PrepareWorkspace
	Convert(GetChangesetsFromHistory)
	CloneToLocalBareRepository
	CleanUp

	Write-Host "Done!"
}

Main
