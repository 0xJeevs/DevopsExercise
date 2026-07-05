import os
import boto3
from flask import Flask, request, jsonify
from botocore.exceptions import ClientError

app = Flask(__name__)

# Initialize DynamoDB client
# The SDK automatically discovers credentials injected via EKS IRSA environment variables:
# - AWS_ROLE_ARN
# - AWS_WEB_IDENTITY_TOKEN_FILE
region = os.environ.get('AWS_REGION', 'ap-south-1')
dynamodb = boto3.resource('dynamodb', region_name=region)
table_name = os.environ.get('DYNAMODB_TABLE', 'customer-data')
table = dynamodb.Table(table_name)

@app.route('/healthz', methods=['GET'])
def healthz():
    try:
        # Simple read verification to check database connection health
        table.meta.client.describe_table(TableName=table_name)
        return jsonify({"status": "healthy"}), 200
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500

# 1. READ Customer (GetItem)
@app.route('/customer/<customer_id>', methods=['GET'])
def get_customer(customer_id):
    try:
        response = table.get_item(Key={'customer_id': customer_id})
        if 'Item' in response:
            return jsonify(response['Item']), 200
        else:
            return jsonify({"error": "Customer not found"}), 404
    except ClientError as e:
        app.logger.error(f"Failed to read from DynamoDB: {e.response['Error']['Message']}")
        return jsonify({"error": e.response['Error']['Message']}), 500

# 2. WRITE Customer (PutItem)
@app.route('/customer', methods=['POST'])
def create_customer():
    data = request.get_json()
    if not data or 'customer_id' not in data or 'name' not in data:
        return jsonify({"error": "Missing required fields (customer_id, name)"}), 400
    
    try:
        table.put_item(Item=data)
        return jsonify({"message": "Customer created successfully"}), 201
    except ClientError as e:
        app.logger.error(f"Failed to write to DynamoDB: {e.response['Error']['Message']}")
        return jsonify({"error": e.response['Error']['Message']}), 500

# 3. UPDATE Customer (UpdateItem)
@app.route('/customer/<customer_id>', methods=['PUT'])
def update_customer(customer_id):
    data = request.get_json()
    if not data or 'name' not in data:
        return jsonify({"error": "Missing field 'name' to update"}), 400
    
    try:
        response = table.update_item(
            Key={'customer_id': customer_id},
            UpdateExpression="set #n = :val",
            ExpressionAttributeNames={"#n": "name"},
            ExpressionAttributeValues={":val": data['name']},
            ReturnValues="UPDATED_NEW"
        )
        return jsonify({"message": "Customer updated successfully", "attributes": response.get('Attributes')}), 200
    except ClientError as e:
        app.logger.error(f"Failed to update DynamoDB: {e.response['Error']['Message']}")
        return jsonify({"error": e.response['Error']['Message']}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
