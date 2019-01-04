#!/bin/bash
EC2_REGION=$5

if [[ -z ${ROLE_SESSION_NAME} || -z ${ROLE_ARN} ]];
 then
    echo "ROLE_SESSION_NAME or ROLE_ARN env variables are unset";
 else
   export credentials=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "$ROLE_SESSION_NAME" | /usr/bin/jq -r ".Credentials")
   # these env variables should be locally scoped to this function
   # thus applying only to the aws route53 command following
   export AWS_ACCESS_KEY_ID=$(echo $credentials | /usr/bin/jq -r ".AccessKeyId")
   export AWS_SECRET_ACCESS_KEY=$(echo $credentials | /usr/bin/jq -r ".SecretAccessKey")
   export AWS_SECURITY_TOKEN=$(echo $credentials | /usr/bin/jq -r ".SessionToken");

fi

RECORDSET_JSON='{
    "HostedZoneId": "'$1'",
    "ChangeBatch": {
        "Comment": "",
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "'$2'",
                    "Type": "A",
                    "TTL": '$3',
                    "ResourceRecords": [
                        {
                            "Value": "'$4'"
                        }
                    ]
                }
            }
        ]
    }
}'

echo 'calling route53 change-resource-record-sets with input json:'
echo $RECORDSET_JSON

export ROUTE53_CHANGE_ID=$(
$LOCAL_BINDIR/aws route53 change-resource-record-sets --cli-input-json "$RECORDSET_JSON" | /usr/bin/jq -r ".ChangeInfo.Id")

#echo 'Waiting for Route53 Recordset Change with ID:'
#echo $ROUTE53_CHANGE_ID

#$LOCAL_BINDIR/aws route53 wait resource-record-sets-changed --region $EC2_REGION --id $ROUTE53_CHANGE_ID
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export AWS_SECURITY_TOKEN=
