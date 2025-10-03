#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DataStack } from '../lib/data-stack';
import { AthenaStack } from '../lib/athena-stack';

// AWS Account and Region configuration
const AWS_ACCOUNT = '699027953523';
const AWS_REGION = 'us-west-2';

const app = new cdk.App();

// Environment configuration
const env = {
  account: AWS_ACCOUNT,
  region: AWS_REGION,
};

// Create DataStack (S3, Glue Database, Crawler)
const dataStack = new DataStack(app, 'LeanAnalyticsDataStack', {
  env,
  description: 'Data layer: S3 bucket, Glue database, and crawler for lean analytics platform',
  tags: {
    Project: 'LeanAnalytics',
    Environment: 'prod',
    Owner: 'DataTeam',
  },
});

// Create AthenaStack (WorkGroup, Named Queries)
const athenaStack = new AthenaStack(app, 'LeanAnalyticsAthenaStack', {
  env,
  description: 'Query layer: Athena WorkGroup and named queries for lean analytics platform',
  tags: {
    Project: 'LeanAnalytics',
    Environment: 'prod',
    Owner: 'DataTeam',
  },
  // Pass DataStack outputs as dependencies
  dataBucket: dataStack.dataBucket,
  glueDatabase: dataStack.glueDatabase,
});

// Explicit dependency to ensure DataStack deploys first
athenaStack.addDependency(dataStack);

new cdk.CfnOutput(dataStack, 'DataBucketName', {
  value: dataStack.dataBucket.bucketName,
  description: 'S3 bucket name for datasets and query results',
  exportName: 'LeanAnalytics-DataBucket',
});

new cdk.CfnOutput(dataStack, 'GlueDatabaseName', {
  value: dataStack.glueDatabase.ref,
  description: 'Glue database name for data catalog',
  exportName: 'LeanAnalytics-GlueDatabase',
});

new cdk.CfnOutput(dataStack, 'GlueCrawlerName', {
  value: dataStack.glueCrawler.name || 'lean-analytics-crawler',
  description: 'Glue crawler name for schema discovery',
  exportName: 'LeanAnalytics-GlueCrawler',
});

new cdk.CfnOutput(athenaStack, 'AthenaWorkGroupName', {
  value: athenaStack.workGroup.name || 'lean_demo_wg',
  description: 'Athena WorkGroup name for query execution',
  exportName: 'LeanAnalytics-AthenaWorkGroup',
});

new cdk.CfnOutput(athenaStack, 'NamedQueriesCount', {
  value: athenaStack.namedQueries.length.toString(),
  description: 'Number of named queries available',
  exportName: 'LeanAnalytics-NamedQueriesCount',
});