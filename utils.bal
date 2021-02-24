// Copyright (c) 2021 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/crypto;
import ballerina/encoding;
import ballerina/http;
import ballerina/lang.'string;
import ballerina/lang.array;
import ballerina/regex;
import ballerina/time;

# Extract the type of token used for accessing the Cosmos DB.
# 
# + token - The token provided by the user to access Cosmos DB
# + return - A string value which represents the type of token
isolated function getTokenType(string token) returns string {
    boolean ifContain = 'string:includes(token, TOKEN_TYPE_RESOURCE);
    if (ifContain) {
        return TOKEN_TYPE_RESOURCE;
    } else {
        return TOKEN_TYPE_MASTER;
    }
}

# Extract the host of the Cosmos DB from the base URL.
# 
# + url - The Base URL given by the user from which we want to extract host
# + return - String representing the resource id
isolated function getHost(string url) returns string {
    string replacedString = regex:replaceFirst(url, HTTPS_REGEX, EMPTY_STRING);
    int? lastIndex = 'string:lastIndexOf(replacedString, FORWARD_SLASH);
    if (lastIndex is int) {
        replacedString = replacedString.substring(0, lastIndex);
    }
    return replacedString;
}

# Extract the resource type related to Cosmos DB from a given URL.
# 
# + url - The URL from which we want to extract resource type
# + return - String representing the resource type
isolated function getResourceType(string url) returns string {
    string resourceType = EMPTY_STRING;
    string[] urlParts = regex:split(url, FORWARD_SLASH);
    int count = urlParts.length() - 1;
    if (count % 2 != 0) {
        resourceType = urlParts[count];
        if (count > 1) {
            int? lastIndex = 'string:lastIndexOf(url, FORWARD_SLASH);
        }
    } else {
        resourceType = urlParts[count - 1];
    }
    return resourceType;
}

# Extract the resource ID related to Cosmos DB from a given URL.
# 
# + url - The URL from which we want to extract resource type
# + return - String representing the resource id
isolated function getResourceId(string url) returns string {
    string resourceId = EMPTY_STRING;
    string[] urlParts = regex:split(url, FORWARD_SLASH);
    int count = urlParts.length() - 1;
    string resourceType = getResourceType(url);
    if (resourceType == RESOURCE_TYPE_OFFERS) {
        if (count % 2 != 0) {
            resourceId = EMPTY_STRING;
        } else {
            int? lastIndex = 'string:lastIndexOf(url, FORWARD_SLASH);
            if (lastIndex is int) {
                resourceId = 'string:substring(url, lastIndex + 1);
            }
        }
        return resourceId.toLowerAscii();
    } else {
        if (count % 2 != 0) {
            if (count > 1) {
                int? lastIndex = 'string:lastIndexOf(url, FORWARD_SLASH);
                if (lastIndex is int) {
                    resourceId = 'string:substring(url, 1, lastIndex);
                }
            }
        } else {
            resourceId = 'string:substring(url, 1);
        }
        return resourceId;
    }
}

# Prepare the complete URL out of a given string array. 
# 
# + paths - Array of strings with parts of the URL
# + return - String representing the complete URL
isolated function prepareUrl(string[] paths) returns string {
    string url = EMPTY_STRING;
    if (paths.length() > 0) {
        foreach var path in paths {
            if (!path.startsWith(FORWARD_SLASH)) {
                url = url + FORWARD_SLASH;
            }
            url = url + path;
        }
    }
    return <@untainted>url;
}

# Attach mandatory basic headers to call a REST endpoint.
# 
# + request - The http:Request to add headers to
# + host - The host to which the request is sent
# + token - Master or resource token
# + httpVerb - The HTTP verb of the request the headers are set to
# + requestPath - Request path for the request
# + return - If successful, request will be appended with headers. Else returns error or nil.
isolated function setMandatoryHeaders(http:Request request, string host, string token, string httpVerb, 
        string requestPath) returns error? {
    request.setHeader(API_VERSION_HEADER, API_VERSION);
    request.setHeader(HOST_HEADER, host);
    request.setHeader(ACCEPT_HEADER, ACCEPT_ALL);
    request.setHeader(http:CONNECTION, CONNECTION_KEEP_ALIVE);
    string tokenType = getTokenType(token);
    string dateTime = check getDateTime();
    request.setHeader(DATE_HEADER, dateTime);
    string signature = "";
    if (tokenType.toLowerAscii() == TOKEN_TYPE_MASTER) {
        signature = check generateMasterTokenSignature(httpVerb, getResourceType(requestPath), 
                getResourceId(requestPath), token, tokenType, dateTime);
    } else if (tokenType.toLowerAscii() == TOKEN_TYPE_RESOURCE) {
        signature = check encoding:encodeUriComponent(token, UTF8_URL_ENCODING);
    } else {
        return prepareUserError(NULL_RESOURCE_TYPE_ERROR);
    }
    request.setHeader(http:AUTH_HEADER, signature);
}

# Set the optional header related to partitionkey value.
#
# + request - The http:Request to set the header
# + partitionKeyValue - The value of the partition key
isolated function setPartitionKeyHeader(http:Request request, (int|float|decimal|string)? partitionKeyValue) {
    if (partitionKeyValue is (int|float|decimal|string)) {
        request.setHeader(PARTITION_KEY_HEADER, string `[${partitionKeyValue.toString()}]`);
    }
    return;
}

# Set the required headers related to query operations.
#
# + request - The http:Request to set the header
# + return - Returns error
isolated function setHeadersForQuery(http:Request request) returns error? {
    check request.setContentType(CONTENT_TYPE_QUERY);
    request.setHeader(ISQUERY_HEADER, TRUE);
}

# Set the optional header related to throughput options.
#
# + request - The http:Request to set the header
# + throughputOption - Throughput parameter of type int or json
# + return - If successful, request will be appended with headers. Else returns error or nil.
isolated function setThroughputOrAutopilotHeader(http:Request request, (int|record{|int maxThroughput;|})? 
        throughputOption = ()) returns error? {
    if (throughputOption is int) {
        if (throughputOption >= MIN_REQUEST_UNITS) {
            request.setHeader(THROUGHPUT_HEADER, throughputOption.toString());
        } else {
            return prepareUserError(MINIMUM_MANUAL_THROUGHPUT_ERROR);
        }
    } else if (throughputOption is record{|int maxThroughput;|}) {
        request.setHeader(AUTOPILET_THROUGHPUT_HEADER, throughputOption.toString());
    } else {
        return;
    }
}

# Set the optional headers to the HTTP request.
#
# + request - The http:Request to set the header
# + requestOptions - Record of type Options containing the values for optional headers
isolated function setOptionalHeaders(http:Request request, Options? requestOptions) {
    if (requestOptions?.indexingDirective is IndexingDirective) {
        request.setHeader(INDEXING_DIRECTIVE_HEADER, <string>requestOptions?.indexingDirective);
    }
    if (requestOptions?.consistancyLevel is ConsistencyLevel) {
        request.setHeader(CONSISTANCY_LEVEL_HEADER, <string>requestOptions?.consistancyLevel);
    }
    if (requestOptions?.sessionToken is string) {
        request.setHeader(SESSION_TOKEN_HEADER, <string>requestOptions?.sessionToken);
    }
    if (requestOptions?.changeFeedOption is ChangeFeedOption){
        request.setHeader(A_IM_HEADER, <string>requestOptions?.changeFeedOption);
    }
    if (requestOptions?.partitionKeyRangeId is string) {
        request.setHeader(PARTITIONKEY_RANGE_HEADER, <string>requestOptions?.partitionKeyRangeId);
    }
    if (requestOptions?.enableCrossPartition == true) {
        request.setHeader(IS_ENABLE_CROSS_PARTITION_HEADER, TRUE);
    }
    if (requestOptions?.isUpsertRequest == true) {
        request.setHeader(IS_UPSERT_HEADER, TRUE);
    }
}

# Set the optional header specifying Time To Live for token.
#
# + request - The http:Request to set the header
# + validityPeriodInSeconds - An integer specifying the Time To Live value for a permission token
# + return - If successful, request will be appended with headers. Else returns error or nil.
isolated function setExpiryHeader(http:Request request, int validityPeriodInSeconds) returns error? {
    if (validityPeriodInSeconds >= MIN_TIME_TO_LIVE_IN_SECONDS && validityPeriodInSeconds <= 
            MAX_TIME_TO_LIVE_IN_SECONDS) {
        request.setHeader(EXPIRY_HEADER, validityPeriodInSeconds.toString());
    } else {
        return prepareUserError(VALIDITY_PERIOD_ERROR);
    }
}

# Get the current time(GMT) in the specific format.
#
# + return - If successful, returns string representing UTC date and time 
#          (in `HTTP-date` format as defined by RFC 7231 Date/Time Formats). Else returns error.
isolated function getDateTime() returns string|error {
    time:Time currentTime = time:currentTime();
    time:Time timeWithZone = check time:toTimeZone(currentTime, GMT_ZONE);
    return check time:format(timeWithZone, TIME_ZONE_FORMAT);
}

# To construct the hashed token signature for a token to set 'Authorization' header.
# 
# + verb - HTTP verb, such as GET, POST, or PUT
# + resourceType - Identifies the type of resource that the request is for, Eg. `dbs`, `colls`, `docs`
# + resourceId - Identity property of the resource that the request is directed at
# + token - master or resource token
# + tokenType - denotes the type of token: master or resource
# + date - current GMT date and time
# + return - If successful, returns string which is the hashed token signature. Else returns error.
isolated function generateMasterTokenSignature(string verb, string resourceType, string resourceId, string token, 
        string tokenType, string date) returns string|error {
    string payload = string `${verb.toLowerAscii()}${NEW_LINE}${resourceType.toLowerAscii()}${NEW_LINE}${resourceId}`
            + string `${NEW_LINE}${date.toLowerAscii()}${NEW_LINE}${EMPTY_STRING}${NEW_LINE}`;
    byte[] decodedArray = check array:fromBase64(token); 
    byte[] digest = check crypto:hmacSha256(payload.toBytes(), decodedArray);
    string signature = array:toBase64(digest);
    string authorizationString = string `type=${tokenType}&ver=${TOKEN_VERSION}&sig=${signature}`;
    return check encoding:encodeUriComponent(authorizationString, "UTF-8");
}

# Handle success or error responses to requests and extract the JSON payload.
#
# + httpResponse - The http:Response returned from an HTTP request
# + return - If successful, returns json. Else returns error. 
isolated function handleResponse(http:Response httpResponse) returns @tainted json|error {
    json jsonResponse = check httpResponse.getJsonPayload();
    if (httpResponse.statusCode is http:STATUS_OK|http:STATUS_CREATED) {
        return jsonResponse;
    }
    string message = let var msg = jsonResponse.message in msg is string ? msg : REST_API_INVOKING_ERROR;
    return prepareAzureError(message, (), httpResponse.statusCode);
}

# Handle success or error responses to requests which does not need to return a payload.
# 
# + httpResponse - The http:Response returned from an HTTP request
# + return - If successful, returns true. Else returns error or nil. 
isolated function handleHeaderOnlyResponse(http:Response httpResponse) returns @tainted error? {
    if (httpResponse.statusCode is http:STATUS_OK|http:STATUS_NO_CONTENT) {
        //If status is 200 the resource is replaced, 201 resource is created, request is successful returns true. 
        // Else Returns error.
        return;
    } else {
        json jsonResponse = check httpResponse.getJsonPayload();
        string message = let var msg = jsonResponse.message in msg is string ? msg : REST_API_INVOKING_ERROR;
        return prepareAzureError(message, (), httpResponse.statusCode);
    }
}

# Get a stream of JSON documents which is returned as query results.
# 
# + azureCosmosClient - Client which calls the azure endpoint
# + path - Path to which API call is made
# + request - HTTP request object 
# + return - A stream<json>
function getQueryResults(http:Client azureCosmosClient, string path, http:Request request) returns 
        @tainted stream<json>|stream<Document>|error {
    http:Response response = <http:Response> check azureCosmosClient->post(path, request);
    json payload = check handleResponse(response);

    if (payload.Documents is json) {
        json[] array = let var load = payload.Documents in load is json ? <json[]>load : [];
        //json[] array = <json[]>payload.Documents;
        Document[] documents = convertToDocumentArray(array);
        return (<@untainted>documents).toStream();
    } else if (payload.Offers is json) {
        json[] array = let var load = payload.Documents in load is json ? <json[]>load : [];
        //json[] array = <json[]>payload.Offers;
        return array.toStream();
    }
    else {
        return prepareAzureError(INVALID_RESPONSE_PAYLOAD_ERROR);
    }
}

# Make a request call to the azure endpoint to get a list of resources.
# 
# + azureCosmosClient - Client which calls the azure endpoint
# + path - Path to which API call is made
# + request - HTTP request object 
# + return - A stream<record{}>
function retrieveStream(http:Client azureCosmosClient, string path, http:Request request) returns @tainted 
        stream<record{}>|error {
    http:Response response = <http:Response> check azureCosmosClient->get(path, request);
    json payload = check handleResponse(response);
    return check createStream(path, payload);
}

# Create a stream from the array obtained from the request call.
# 
# + path - Path to which API call is made
# + payload - JSON payload returned from the response
# + return - A stream<record{}> or error
isolated function createStream(string path, json payload) returns @tainted stream<record{}>|error {
    record{}[] finalArray = [];
    if (payload.Databases is json) {
        json[] array = let var load = payload.Databases in load is json ? <json[]>load : [];
        finalArray = convertToDatabaseArray(array);
    } else if (payload.DocumentCollections is json) {
        json[] array = let var load = payload.DocumentCollections in load is json ? <json[]>load : [];
        finalArray = convertToContainerArray(array);
    } else if (payload.Documents is json) {
        json[] array = let var load = payload.Documents in load is json ? <json[]>load : [];
        finalArray = convertToDocumentArray(array);
    } else if (payload.StoredProcedures is json) {
        json[] array = let var load = payload.StoredProcedures in load is json ? <json[]>load : [];
        finalArray = convertToStoredProcedureArray(array);
    } else if (payload.UserDefinedFunctions is json) {
        json[] array = let var load = payload.UserDefinedFunctions in load is json ? <json[]>load : [];
        finalArray = convertsToUserDefinedFunctionArray(array);
    } else if (payload.Triggers is json) {
        json[] array = let var load = payload.Triggers in load is json ? <json[]>load : [];
        finalArray = convertToTriggerArray(array);
    } else if (payload.Users is json) {
        json[] array = let var load = payload.Users in load is json ? <json[]>load : [];
        finalArray = convertToUserArray(array);
    } else if (payload.Permissions is json) {
        json[] array = let var load = payload.Permissions in load is json ? <json[]>load : [];
        finalArray = convertToPermissionArray(array);
    } else if (payload.PartitionKeyRanges is json) {
        json[] array = let var load = payload.PartitionKeyRanges in load is json ? <json[]>load : [];
        finalArray = convertToPartitionKeyRangeArray(array);
    } else if (payload.Offers is json) {
        json[] array = let var load = payload.Offers in load is json ? <json[]>load : [];
        finalArray = convertToOfferArray(array);
    } else {
        return prepareAzureError(INVALID_RESPONSE_PAYLOAD_ERROR);
    }
    return (<@untainted>finalArray).toStream();
}

# Get the enum value for a given string which represents the type of index.
#
# + kind - The index type
# + return - An enum value of `IndexType`
isolated function getIndexType(string kind) returns IndexType {
    match kind {
        "Range" => {
            return RANGE;
        }
        "Spatial" => {
            return SPATIAL;
        }
    }
    return HASH;
}

# Get the enum value for a given string which represents the indexing mode of index.
#
# + mode - The indexing mode of container
# + return - An enum value of `IndexingMode` 
isolated function getIndexingMode(string mode) returns IndexingMode {
    match mode {
        "consistent" => {
            return CONSISTENT;
        }
    }
    return NONE;
}

# Get the enum value for a given string which represents the data type index is applied to.
#
# + dataType - The string representing the data type index have applied to
# + return - An enum value of `IndexDataType` 
isolated function getIndexDataType(string dataType) returns IndexDataType {
    match dataType {
        "Number" => {
            return NUMBER;
        }
        "Point" => {
            return POINT;
        }
        "Polygon" => {
            return POLYGON;
        }
        "LineString" => {
            return LINESTRING;
        }
    }
    return STRING;
}

# Get the enum value for a given string which represent the operation a trigger is applied to.
#
# + triggerOperation - The string representing the operation which is capable of firing the trigger
# + return - An enum value of `TriggerOperation` 
isolated function getTriggerOperation(string triggerOperation) returns TriggerOperation {
    match triggerOperation {
        "Create" => {
            return CREATE;
        }
        "Replace" => {
            return REPLACE;
        }
        "Delete" => {
            return DELETE;
        }
    }
    return ALL;
}

# Get the enum value for a given string which represent when the trigger is fired.
#
# + triggerType - The string representing when the trigger will be fired
# + return - An enum value of `TriggerType`
isolated function getTriggerType(string triggerType) returns TriggerType {
    match triggerType {
        "Post" => {
            return POST;
        }
    }
    return PRE;
}

# Get the enum value for a given string which represent the access rights for the specific permission.
#
# + permissionMode - The string representing the permisssionMode
# + return - An enum value of `PermisssionMode`
isolated function getPermisssionMode(string permissionMode) returns PermisssionMode {
    match permissionMode {
        "Read" => {
            return READ_PERMISSION;
        }
    }
    return ALL_PERMISSION;
}

# Get the enum value for a given string which represent the offer version of a specific offer.
#
# + offerVersion - The string representing the offer version
# + return - An enum value of `PermisssionMode`
isolated function getOfferVersion(string offerVersion) returns OfferVersion {
    match offerVersion {
        "V1" => {
            return PRE_DEFINED;
        }
    }
    return USER_DEFINED;
}

# Get the enum value for a given string which represent the offer type of a specific offer.
#
# + offerType - The string representing the offer type
# + return - An enum value of `OfferType`
isolated function getOfferType(string offerType) returns OfferType {
    match offerType {
        "S1" => {
            return LEVEL_S1;
        }
        "S2" => {
            return LEVEL_S2;
        }
        "S3" => {
            return LEVEL_S3;
        }
    }
    return INVALID;
}

# Get the const value for a given integer which represent the version of a specific partition key.
#
# + partitionKeyVersion - An integer representing the version of partition key
# + return - An const value of `PartitionKeyVersion`
isolated function getPartitionKeyVersion(int partitionKeyVersion) returns PartitionKeyVersion {
    match partitionKeyVersion {
        1 => {
            return PARTITION_KEY_VERSION_2;
        }
    }
    return PARTITION_KEY_VERSION_1;
}
