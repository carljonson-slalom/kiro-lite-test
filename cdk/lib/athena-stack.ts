import * as cdk from 'aws-cdk-lib';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

interface AthenaStackProps extends cdk.StackProps {
  dataBucket: s3.Bucket;
  glueDatabase: glue.CfnDatabase;
}

export class AthenaStack extends cdk.Stack {
  public readonly workGroup: athena.CfnWorkGroup;
  public readonly namedQueries: athena.CfnNamedQuery[];

  constructor(scope: Construct, id: string, props: AthenaStackProps) {
    super(scope, id, props);

    const { dataBucket, glueDatabase } = props;

    // Athena WorkGroup for query execution
    this.workGroup = new athena.CfnWorkGroup(this, 'LeanAnalyticsWorkGroup', {
      name: 'lean_demo_wg',
      description: 'WorkGroup for lean analytics demo queries with result location and cost controls',
      state: 'ENABLED',
      
      workGroupConfiguration: {
        // Result configuration
        resultConfiguration: {
          outputLocation: `s3://${dataBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        
        // Enforce WorkGroup configuration
        enforceWorkGroupConfiguration: true,
        
        // Bytes scanned cutoff for cost control (100 MB for demo)
        bytesScannedCutoffPerQuery: 100 * 1024 * 1024,
        
        // Require result location
        requesterPaysEnabled: false,
        
        // Engine version
        engineVersion: {
          selectedEngineVersion: 'Athena engine version 3',
          effectiveEngineVersion: 'Athena engine version 3',
        },
      },
      
      tags: [
        {
          key: 'Project',
          value: 'LeanAnalytics',
        },
        {
          key: 'Component',
          value: 'AthenaStack',
        },
        {
          key: 'Environment',
          value: 'demo',
        },
      ],
    });

    // Named Query 1: Top 10 orders by order_total
    const topOrdersQuery = new athena.CfnNamedQuery(this, 'TopOrdersQuery', {
      name: 'top_10_orders_by_total',
      description: 'Top 10 orders by order_total - Shows highest value orders',
      database: glueDatabase.ref,
      workGroup: this.workGroup.name,
      queryString: `
-- Top 10 orders by order_total
-- Shows the highest value orders with customer and date information
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    c.email,
    o.order_date,
    o.order_total,
    o.status
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_total DESC
LIMIT 10;
      `.trim(),
    });

    // Named Query 2: Returns by customer (LEFT JOIN)
    const returnsByCustomerQuery = new athena.CfnNamedQuery(this, 'ReturnsByCustomerQuery', {
      name: 'returns_by_customer',
      description: 'Returns by customer using LEFT JOIN - Shows all customers and their returns if any',
      database: glueDatabase.ref,
      workGroup: this.workGroup.name,
      queryString: `
-- Returns by customer (LEFT JOIN)
-- Shows all customers and their return information (if any)
-- Includes customers who haven't made returns
SELECT 
    c.customer_id,
    c.customer_name,
    c.email,
    c.registration_date,
    r.return_id,
    r.order_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    CASE 
        WHEN r.return_id IS NOT NULL THEN 'Has Returns'
        ELSE 'No Returns'
    END AS return_status
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
LEFT JOIN returns r ON o.order_id = r.order_id
ORDER BY c.customer_name, r.return_date DESC;
      `.trim(),
    });

    // Named Query 3: Orders that were returned
    const returnedOrdersQuery = new athena.CfnNamedQuery(this, 'ReturnedOrdersQuery', {
      name: 'orders_that_were_returned',
      description: 'Orders that were returned using INNER JOIN - Shows only orders with returns',
      database: glueDatabase.ref,
      workGroup: this.workGroup.name,
      queryString: `
-- Orders that were returned
-- Shows only orders that have corresponding returns
-- Includes return details and financial impact
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_name,
    o.order_date,
    o.order_total,
    o.status AS order_status,
    r.return_id,
    r.return_date,
    r.return_reason,
    r.refund_amount,
    (o.order_total - r.refund_amount) AS net_revenue,
    ROUND((r.refund_amount / o.order_total) * 100, 2) AS return_percentage
FROM orders o
INNER JOIN returns r ON o.order_id = r.order_id
INNER JOIN customers c ON o.customer_id = c.customer_id
ORDER BY o.order_date DESC, r.return_date DESC;
      `.trim(),
    });

    // Store named queries for reference
    this.namedQueries = [
      topOrdersQuery,
      returnsByCustomerQuery,
      returnedOrdersQuery,
    ];

    // IAM role for Athena query execution (for local development access)
    const athenaExecutionRole = new iam.Role(this, 'AthenaExecutionRole', {
      roleName: `LeanAnalytics-AthenaExecution-${cdk.Stack.of(this).region}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('athena.amazonaws.com'),
        // Allow developers to assume this role for local development
        new iam.AccountRootPrincipal(),
      ),
      description: 'IAM role for Athena query execution and S3 result access',
      
      inlinePolicies: {
        'AthenaExecutionPolicy': new iam.PolicyDocument({
          statements: [
            // Athena permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'athena:BatchGetQueryExecution',
                'athena:GetQueryExecution',
                'athena:GetQueryResults',
                'athena:GetQueryResultsStream',
                'athena:StartQueryExecution',
                'athena:StopQueryExecution',
                'athena:ListQueryExecutions',
                'athena:GetWorkGroup',
                'athena:GetNamedQuery',
                'athena:ListNamedQueries',
                'athena:GetDataCatalog',
                'athena:ListDataCatalogs',
              ],
              resources: [
                `arn:aws:athena:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:workgroup/${this.workGroup.name}`,
                `arn:aws:athena:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:datacatalog/*`,
              ],
            }),
            // Glue Data Catalog permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:GetDatabase',
                'glue:GetDatabases',
                'glue:GetTable',
                'glue:GetTables',
                'glue:GetPartitions',
                'glue:GetPartition',
                'glue:BatchGetPartition',
              ],
              resources: [
                `arn:aws:glue:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:catalog`,
                `arn:aws:glue:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:database/${glueDatabase.ref}`,
                `arn:aws:glue:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:table/${glueDatabase.ref}/*`,
              ],
            }),
            // S3 permissions for data access and results
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketLocation',
                's3:GetObject',
                's3:ListBucket',
                's3:ListBucketMultipartUploads',
                's3:ListMultipartUploadParts',
                's3:AbortMultipartUpload',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                dataBucket.bucketArn,
                `${dataBucket.bucketArn}/datasets/*`,
                `${dataBucket.bucketArn}/athena-results/*`,
              ],
            }),
          ],
        }),
      },
    });

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'AthenaWorkGroupOutput', {
      value: this.workGroup.name!,
      description: 'Athena WorkGroup name for query execution',
      exportName: `${cdk.Stack.of(this).stackName}-WorkGroup`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkGroupArnOutput', {
      value: `arn:aws:athena:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:workgroup/${this.workGroup.name}`,
      description: 'ARN of the Athena WorkGroup',
      exportName: `${cdk.Stack.of(this).stackName}-WorkGroupArn`,
    });

    new cdk.CfnOutput(this, 'AthenaResultLocationOutput', {
      value: `s3://${dataBucket.bucketName}/athena-results/`,
      description: 'S3 location for Athena query results',
      exportName: `LeanAnalyticsAthenaStack-ResultLocation`,
    });

    new cdk.CfnOutput(this, 'NamedQueriesOutput', {
      value: this.namedQueries.map(q => q.name!).join(', '),
      description: 'Available named queries for analytics',
      exportName: `LeanAnalyticsAthenaStack-NamedQueries`,
    });

    new cdk.CfnOutput(this, 'AthenaExecutionRoleOutput', {
      value: athenaExecutionRole.roleArn,
      description: 'IAM role ARN for Athena query execution',
      exportName: `LeanAnalyticsAthenaStack-ExecutionRole`,
    });

    new cdk.CfnOutput(this, 'QueryDatabaseOutput', {
      value: glueDatabase.ref,
      description: 'Glue database name for Athena queries',
      exportName: `LeanAnalyticsAthenaStack-Database`,
    });

    // Sample queries for testing
    new cdk.CfnOutput(this, 'SampleQueriesOutput', {
      value: [
        'SELECT COUNT(*) FROM customers;',
        'SELECT COUNT(*) FROM orders;',
        'SELECT COUNT(*) FROM returns;',
        'SHOW TABLES;',
        'DESCRIBE customers;',
      ].join(' | '),
      description: 'Sample queries to test Athena setup',
      exportName: `LeanAnalyticsAthenaStack-SampleQueries`,
    });

    // Add tags to all resources in this stack
    cdk.Tags.of(this).add('Project', 'LeanAnalytics');
    cdk.Tags.of(this).add('Component', 'AthenaStack');
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('ManagedBy', 'AWS-CDK');
  }
}