#!/bin/bash

# WorkFlow and Guidelines:
#=========================
#=========================

# Normal AWS-Codepipline at One Account:
# =====================================
# AWS CodePipeline always automates the creation of three main services in background: 
        # 1. S3 as Artifact Store 
        # 2. KMS key for encryption of Artifacts Code.
        # 3. IAM roles: Codepipeline Role + Role for Each stage of Source & Build --> Codepipline role assumes them.


# Cross Account AWS-Codepipline Approach Considerations:
# ======================================================
# To be able to apply multi-Account CodePipeline, i need to consider the following:
        # Create and adjust the above three elements yourself from scratch.
        # Each stage from Source to Build MUST have the required permissions to access the above created elements. 
        # Use an automated IAC approach like CloudFormation integrated with a scripting technology like Bash.

# The Final Approach:
#=====================
# the Bash Script that applies the above considerations should do the following:
        # 1. Deploy a Flow of Pre-requestes stacks that creates the above Three main services manually.
        # 2. Deploy the Code-pipeline stack that creates the Three stages of the Pipeline referncing the required IAM roles and KMS key.
        # 3. Give the Source & Build stage the required permissions by updating the pre-req stack with codebuild-role and updating codepipline stack with the Source IAM role.


# What is the Magic of the wand??
# ===============================
# this approach is mainly built in one Magic Idea: "Give Source and Build Stages the Required Permissions"
# Source Permissions:
        # Fetch codecommit code, encrypt it with KMS, store it in s3 artifact store
# Build Stage:
        # Decrypt Code with same KMS key, Store Built Artifact at S3 store.


# When to give them the required Permissions? 
# ===========================================
# Normally, Deploy two Pre-req stacks (DevAccount IAM role, DeployAccount S3 and KMS)
        # Note: you must let the Condition of "AddCodeBuildResource" to "false" as is, but why??
        # it does not make sense to add permissions for Pipeline CodeBuild Build stage by mentioning its role BEFORE creating the Build stage and build Project themselves.
        # the default for condition is false, so you will notice that it will not give KMS principals to be accessed by any Build Role
# then, Deploy Codepipline stack (Contains three pipleline stages, Codepipeline Role, and the CodeBuild BuildProject Configurations)
        # Note: you should let the Condition of "CodeBuildRoleUpdatedAtKMS" to "false" as is, but why??
        # it will not quite wise to give permission to Source stage to be able to fetch and store the code at s3, and at the next stage of Build the Build Stage will not be able to build the code.
        # this because, Build stage will not be able to decrypt code untill the CodeBuild Role is added at the KMS principals,

# then, update DeployAccount Pre-req stack:
        # Note: pass the "AddCodeBuildResource" to be "true" instead of the default false, but why?
        # you have already created the Build-Role at the previous stack and now you have its ARN, so adding it make sense

# then, update the Codepipline stack:
        # Note: you must let the Condition of "CodeBuildRoleUpdatedAtKMS" to "true" as is, but why??
        # Now the CodeBuild has permissions to Decrypt code and start doing his function which is the build process.
        # so, now giving the Source stage permission to fetch and store code is undoubtly make sense.

# Note:
        # i was able to give the Source Stageits permission at the source stage, but i wanted all stages to work properly at the same time, not only the source stage
        # so, i waited until build project is created and it's role is availble to be updated at the Pre-req stack specifically at KMS principels



 
#Function to get S3Name & KMSKey existing on Deployment Account for sake of later use.
function get_S3_KMS() {
        #How to determine what CloudFormation stack an AWS resource belongs to using AWS CLI?:
        #https://stackoverflow.com/questions/58724180/how-to-determine-what-cloudformation-stack-an-aws-resource-belongs-to-using-aws

        get_S3_owner_stack="aws cloudformation describe-stack-resources \
        --physical-resource-id "codepipeline-artifact-store-04" \
        --profile 04 --region us-east-1 2>/dev/null | grep -i "StackName" | head -n 1 | cut -d ":" -f 2 | cut -d "," -f 1"
        Current_StackName=$(eval $get_S3_owner_stack)
        echo -e "\nGot Pre-req Stack name > $Current_StackName \n"
	
	
        get_s3_command="aws cloudformation describe-stacks --stack-name $Current_StackName --profile 04 \
        --region us-east-1 --query \"Stacks[0].Outputs[?OutputKey=='ArtifactBucket'].OutputValue\" --output text"
        S3Bucket=$(eval $get_s3_command)
        echo -e "\nGot S3 bucket name > $S3Bucket \n"

        get_cmk_command="aws cloudformation describe-stacks --stack-name $Current_StackName --profile 04 \
        --region us-east-1 --query \"Stacks[0].Outputs[?OutputKey=='CMK'].OutputValue\" --output text"
        CMKArn=$(eval $get_cmk_command)
        echo -e "Got CMK ARN > $CMKArn \n"
}


function pipe_deployment() {

  while true
  do
	echo -e "\nPhase II > Pipeline Deployment on Target AWS Deployment account...\n"

        #Know more about Changing variable value to Uppercase or Lowercase: https://www.shellscript.sh/tips/case/
        echo -n "please Enter Environment Name [Ex.: Live] >  "
        read Environment_Name 
        Environment_Name=${Environment_Name:-"Live"}
        Environment_Name=${Environment_Name,,} 
        Environment_Name=${Environment_Name^}
        echo $Environment_Name

        echo -n "please Enter Build Project Name [Ex.: Bot] >  "
        read Build_ProjectName 
        Build_ProjectName=${Build_ProjectName:-"Bot"}
        Build_ProjectName=${Build_ProjectName,,}
        Build_ProjectName=${Build_ProjectName^}
        echo $Build_ProjectName

        echo -n "please Enter Project Repository Name in CodeCommit >  "
        read RepositoryCodeCommit_Name
        RepositoryCodeCommit_Name=${RepositoryCodeCommit_Name:-"my-repo"}

        echo -n "[Optional] pass in the custom name for buildspec.yaml file if exist [ex.: buildspec-inbox.yaml] >  "
        read CustomBuildSpec
        CustomBuildSpec=${CustomBuildSpec:-"buildspec.yml"}

        echo -n "please Enter Branch Name [EX.: master] >  "
        read Branch_Name
        Branch_Name=${Branch_Name:-"master"}

        echo -n "please Enter Beanstalk Application Name >  "
        read BeansTalkApp_Name
        BeansTalkApp_Name=${BeansTalkApp_Name:-"my-beanstalk-app"}

        echo -n "please Enter Beanstalk Environment Name > "
        read BeansTalkEnv_Name
        BeansTalkEnv_Name=${BeansTalkEnv_Name:-"my-beanstalk-env"}

        echo -n "please Enter Development account-ID [current One: 01234] > "
        read DevAccountID
        DevAccountID=${DevAccountID:-"01234"}
        #Checking Vars empty values.
        if [[ -z $Environment_Name || -z $Build_ProjectName || -z $Branch_Name || -z $DevAccountID || -z $RepositoryCodeCommit_Name || -z $BeansTalkApp_Name || -z $BeansTalkEnv_Name ]];
        then
                echo -e "\nInvalid or Empty Entries, Please Try again!!\n"
        else
                #check if any stack exist and contain resource with the passed physical id.
                #Note: 2>/dev/null -it passes any error away so that if stack does not exist, command exec will 
                #return empty string not "Normal" output error value.

                get_pipeline_owner_stack="aws cloudformation describe-stack-resources \
                --physical-resource-id "WB-$Environment_Name-$Build_ProjectName" \
                --profile 04 --region us-east-1 2>/dev/null \
                | grep -i "StackName" | head -n 1 | cut -d ":" -f 2 | cut -d "," -f 1 2>/dev/null"
                PipeStack_exist=$(eval $get_pipeline_owner_stack)

                if [[ -z $PipeStack_exist ]];
                then
                        #get s3 bucket and CMKArn values 
                        get_S3_KMS
                        echo -e "\nExecuting in DEPLOY Account, Deploying Pipeline on Deployment Account..."
                        exec_pipedeploy="aws cloudformation deploy --stack-name "WB-$Environment_Name-$Build_ProjectName" \
				--template-file $(pwd)/DeployAcct/code-pipeline.yaml \
                                --parameter-overrides DevAccount=$DevAccountID Environment=$Environment_Name \
                                RepositoryCodeCommit=$RepositoryCodeCommit_Name ProjectName=$Build_ProjectName \
                                CMKARN=$CMKArn S3Bucket=$S3Bucket \
                                Branch=$Branch_Name \
                                BeansTalkAppName=$BeansTalkApp_Name \
                                BeansTalkEnvName=$BeansTalkEnv_Name \
                                --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
                        eval $exec_pipedeploy
                        wait
                        echo -e "\nExecuting in DEPLOY Account, Updating KMS in Pre-req stack with Build IAM role..."
                        exec_preReq_update="aws cloudformation deploy --stack-name $Current_StackName \
			--template-file $(pwd)/DeployAcct/pre-reqs.yaml \
                        --parameter-overrides ProjectName=$Build_ProjectName Environment=$Environment_Name CodeBuildCondition=true \
                        --profile 04 --region us-east-1"

                        eval $exec_preReq_update
                        wait
                        echo -e "\nExecuting in DEPLOY Account, Updating Pipeline Source stage with DevAcct IAM role..."
                        exec_pipeUpdate="aws cloudformation deploy --stack-name "WB-$Environment_Name-$Build_ProjectName" \
				--template-file $(pwd)/DeployAcct/code-pipeline.yaml \
                                --parameter-overrides PermitSourceStage=true \
                                --capabilities CAPABILITY_NAMED_IAM --profile 04 --region us-east-1"
                        eval $exec_pipeUpdate
                        wait
			echo -e "\nStack WB-$Environment_Name-$Build_ProjectName has been created Successfully...\n"
                        echo -e "\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\n"

				
                else
                        echo -e "\nStack with name: $PipeStack_exist already exist with the required resources as well.."
				
		
                fi
        fi

  done

}


# ========================================== MAIN EXECUTION =======================================================
# =================================================================================================================

echo "Phase I > Checking and Installing Pre-requesets..."
sleep 2


# 1. S3 Artifact Store
echo -e "\nChecking if the Requested Pre-requesites already installed or not...\n"
S3_bucket="aws s3 ls codepipeline-artifact-store-04 --profile 04 --region us-east-1"
s3_exist=$(eval $S3_bucket 2>/dev/null)
s3_exist=${s3_exist:-"not_found"}


# 2. KMS Encryption Key 
#learn more about KMS and Aliases: https://github.com/awsdocs/aws-kms-developer-guide/blob/master/doc_source/alias-manage.md
KMS_key="aws kms list-aliases --region us-east-1 --profile 04 | grep -x "alias/codepipeline-crossaccounts""
key_exist=$(eval $KMS_key 2>/dev/null) || true
key_exist=${key_exist:-"not_found"}


# 3. Dev Account Assumable Role
Dev_IAM_Role="aws iam list-roles --region us-east-1 --profile default | grep -x "DeploymentAcctCodePipelineCodeCommitRole""
role_exist=$(eval $Dev_IAM_Role 2>/dev/null) || true
role_exist=${role_exist:-"not_found"}

#learn more about grouping in if condition: https://stackoverflow.com/questions/14964805/groups-of-compound-conditions-in-bash-test
if [[ -z "$s3_exist" &&  -z "$key_exist" && -z $role_exist ]];
then
	while true
	do
        	echo -e "\nResources ARE not there, Deploying pre-requisite stack to the Deployment account... \n"

        	echo -n "please Enter preferred CloudFormation StackName For Deployment account pre-req resources >  "
        	read Deploy_PreReq_StackName 
                Deploy_PreReq_StackName=${Deploy_PreReq_StackName:-"default"}
        	echo -n "please Enter preferred CloudFormation StackName For Dev account pre-req resources >  "
        	read Dev_PreReq_StackName 
                Dev_PreReq_StackName=${Dev_PreReq_StackName:-"default"}
       		echo -n "please Enter Dev. account-ID [current One: 01234] > "
        	read DevAccountID 
                DevAccountID=${DevAccountID:-"01234"}
        	echo -n "please Enter Deploy. account-ID [current One: 05678] > "
        	read DeployAccountID 
                DeployAccountID=${DeployAccountID:-"05678"}


        	#Checking Vars empty values.
        	if [[ -z $Deploy_PreReq_StackName || -z $Dev_PreReq_StackName || -z $DevAccountID || -z $DeployAccountID ]];
        	then
                	echo -e "\nInvalid or Empty Entries, Please Try again!!\n"
        	else	
                	#checking if there are stacks with the same name...
                	#NOte: grep with -x option, returns true only if it finds the [exact] match for the passed text,
			#not match a slice part
                	list_DeployStacks="aws cloudformation list-stacks --profile 04 --region us-east-1 \
				| grep -x "$Deploy_PreReq_StackName""
                	DeployStack_exist=$(eval $list_DeployStacks)
                	list_DevStacks="aws cloudformation list-stacks --profile default --region us-east-1 \
				| grep -x "$Dev_PreReq_StackName""
                	DevStack_exist=$(eval $list_DevStacks)

                	if [[ -z $DeployStack_exist && -z $DevStack_exist ]];
                	then
                        	echo -e "\nExecuting in DEPLOY Account, Deploying S3-Artifact-Store & KMS Encryption key..."
                        	exec_deploy="aws cloudformation deploy --stack-name $Deploy_PreReq_StackName \
                        	--template-file $(pwd)/DeployAcct/pre-reqs.yaml \
                        	--parameter-overrides DevAccount=$DevAccountID --profile 04 --region us-east-1"
				eval $exec_deploy
                        	wait

                        	echo -e "\nExecuting in DEV Account, Deploying dev account assumable role..."

                        	#execute function to get S3 and KMS existing on Deployment Account.
				get_S3_KMS

				exec_dev="aws cloudformation deploy --stack-name $Dev_PreReq_StackName \
				--template-file $(pwd)/DevAccount/deployacct-codepipeline-codecommit.yaml \
				--capabilities CAPABILITY_NAMED_IAM \
				--parameter-overrides CMKARN=$CMKArn DevAccount=$DevAccounTID DeploymentAccount=$DeployAccountID \
				--profile default --region us-east-1"
				eval $exec_dev
				
				#Pipeline deployment function execution
				pipe_deployment

			else
				echo -e "\nStack Names $Deploy_PreReq_StackName & $Dev_PreReq_StackName already in-use"			       				break

			fi

	              fi

	done

else
        sleep 1
        echo "The Required Resources already there, Proceeding to the Next Deployment steps..."
        #execute function to get S3 and KMS existing on Deployment Account.
        #get_S3_KMS
        #Pipeline deployment function execution
        pipe_deployment
fi



	
