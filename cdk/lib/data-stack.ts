import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import { Construct } from 'constructs';
import * as path from 'path';

export class DataStack extends cdk.Stack {
  public readonly dataBucket: s3.Bucket;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly glueCrawler: glue.CfnCrawler;
  public readonly crawlerRole: iam.Role;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create unique bucket name with account and region
    const bucketName = `lean-analytics-${this.account}-${this.region}`;

    // S3 Bucket for data storage and Athena results
    this.dataBucket = new s3.Bucket(this, 'LeanAnalyticsDataBucket', {
      bucketName: bucketName,
      versioned: true,
      
      // Lifecycle configuration
      lifecycleRules: [
        {
          id: 'athena-results-cleanup',
          prefix: 'athena-results/',
          expiration: cdk.Duration.days(30),
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'datasets-retention',
          prefix: 'datasets/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      
      // CORS configuration for potential web uploads
      cors: [
        {
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          maxAge: 3000,
        },
      ],
      
      // Enable deletion for prototype (NOT for production)
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      
      // Notification configuration
      eventBridgeEnabled: true,
      
      // Block public access
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Server-side encryption
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // Upload sample CSV data to S3
    new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [s3deploy.Source.asset(path.join(__dirname, '../../data'))],
      destinationBucket: this.dataBucket,
      destinationKeyPrefix: 'datasets/',
      
      // Retain deployments for data integrity
      retainOnDelete: false,
      
      // Metadata for uploaded files
      metadata: {
        'project': 'lean-analytics',
        'data-type': 'sample-csv',
        'created-by': 'cdk-deployment',
        'version': '1.0',
      },
      
      // Cache control
      cacheControl: [s3deploy.CacheControl.maxAge(cdk.Duration.days(30))],
    });

    // IAM Role for Glue Crawler
    this.crawlerRole = new iam.Role(this, 'GlueCrawlerRole', {
      roleName: `LeanAnalytics-GlueCrawlerRole-${this.region}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for Glue Crawler to access S3 data and update catalog',
      
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      
      inlinePolicies: {
        'S3AccessPolicy': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketLocation',
                's3:ListBucketMultipartUploads',
                's3:ListMultipartUploadParts',
                's3:AbortMultipartUpload',
              ],
              resources: [
                this.dataBucket.bucketArn,
                `${this.dataBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:GetDatabase',
                'glue:GetTable',
                'glue:GetTables',
                'glue:CreateTable',
                'glue:UpdateTable',
                'glue:DeleteTable',
                'glue:GetPartition',
                'glue:GetPartitions',
                'glue:CreatePartition',
                'glue:UpdatePartition',
                'glue:DeletePartition',
                'glue:BatchCreatePartition',
                'glue:BatchDeletePartition',
                'glue:BatchUpdatePartition',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Glue Database
    this.glueDatabase = new glue.CfnDatabase(this, 'LeanAnalyticsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'lean_demo_db',
        description: 'Database for lean analytics demo containing customer, order, and return data',
        parameters: {
          'classification': 'csv',
          'created_by': 'aws-cdk',
          'project': 'lean-analytics',
          'environment': 'demo',
        },
      },
    });

    // Glue Crawler
    this.glueCrawler = new glue.CfnCrawler(this, 'LeanAnalyticsCrawler', {
      name: 'lean-analytics-crawler',
      role: this.crawlerRole.roleArn,
      databaseName: this.glueDatabase.ref,
      description: 'Crawls CSV data in S3 to populate Glue Data Catalog for Athena queries',
      
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataBucket.bucketName}/datasets/`,
            exclusions: [
              '**/_SUCCESS',
              '**/.DS_Store',
              '**/Thumbs.db',
            ],
          },
        ],
      },
      
      // Crawler configuration
      configuration: JSON.stringify({
        Version: 1.0,
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' },
        },
        Grouping: {
          TableGroupingPolicy: 'CombineCompatibleSchemas',
        },
      }),
      
      // Schema change policy
      schemaChangePolicy: {
        deleteBehavior: 'LOG',
        updateBehavior: 'UPDATE_IN_DATABASE',
      },
      
      // Recrawl policy
      recrawlPolicy: {
        recrawlBehavior: 'CRAWL_EVERYTHING',
      },
    });

    // EventBridge rule for daily crawler execution
    const crawlerScheduleRule = new events.Rule(this, 'CrawlerScheduleRule', {
      ruleName: 'lean-analytics-crawler-schedule',
      description: 'Triggers Glue crawler daily at 2 AM UTC',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '2',
        day: '*',
        month: '*',
        year: '*',
      }),
      enabled: true,
    });

    // Add Glue crawler as target for the schedule
    crawlerScheduleRule.addTarget(
      new targets.AwsApi({
        service: 'Glue',
        action: 'startCrawler',
        parameters: {
          Name: this.glueCrawler.name,
        },
      }),
    );

    // CloudFormation Outputs
    new cdk.CfnOutput(this, 'DataBucketNameOutput', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket name for data storage',
      exportName: `LeanAnalyticsDataStack-DataBucket`,
    });

    new cdk.CfnOutput(this, 'DataBucketArnOutput', {
      value: this.dataBucket.bucketArn,
      description: 'S3 bucket ARN for data storage',
      exportName: `LeanAnalyticsDataStack-DataBucketArn`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseNameOutput', {
      value: this.glueDatabase.ref,
      description: 'Glue database name for data catalog',
      exportName: `LeanAnalyticsDataStack-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'GlueCrawlerNameOutput', {
      value: this.glueCrawler.name!,
      description: 'Glue crawler name for schema discovery',
      exportName: `LeanAnalyticsDataStack-GlueCrawler`,
    });

    new cdk.CfnOutput(this, 'CrawlerRoleArnOutput', {
      value: this.crawlerRole.roleArn,
      description: 'IAM role ARN for Glue crawler',
      exportName: `LeanAnalyticsDataStack-CrawlerRole`,
    });

    new cdk.CfnOutput(this, 'DatasetLocationOutput', {
      value: `s3://${this.dataBucket.bucketName}/datasets/`,
      description: 'S3 location of uploaded CSV datasets',
      exportName: `LeanAnalyticsDataStack-DatasetLocation`,
    });

    new cdk.CfnOutput(this, 'AthenaResultsLocationOutput', {
      value: `s3://${this.dataBucket.bucketName}/athena-results/`,
      description: 'S3 location for Athena query results',
      exportName: `LeanAnalyticsDataStack-AthenaResultsLocation`,
    });

    // Add tags to all resources in this stack
    cdk.Tags.of(this).add('Project', 'LeanAnalytics');
    cdk.Tags.of(this).add('Component', 'DataStack');
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('ManagedBy', 'AWS-CDK');
  }
}