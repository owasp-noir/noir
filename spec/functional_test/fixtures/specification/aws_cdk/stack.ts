import * as apigw from 'aws-cdk-lib/aws-apigateway';
import { HttpApi, HttpMethod } from 'aws-cdk-lib/aws-apigatewayv2';

const api = new apigw.RestApi(this, 'Api');
const users = api.root.addResource('users');
users.addMethod('GET',  new apigw.LambdaIntegration(listFn));
users.addMethod('POST', new apigw.LambdaIntegration(createFn));

const user = users.addResource('{id}');
user.addMethod('GET',    new apigw.LambdaIntegration(getFn));
user.addMethod('DELETE', new apigw.LambdaIntegration(deleteFn));

const httpApi = new HttpApi(this, 'HttpApi');
httpApi.addRoutes({ path: '/me', methods: [HttpMethod.GET], integration: foo });
