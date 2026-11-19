local utils = require("leetcode.api.utils")

---Editorial, community solutions and submissions for the splits side pane.
local article = {}

---@param cb fun(res?: table, err?: lc.err)
---@param pick fun(data: table): any
local function callback(cb, pick)
    return function(res, err)
        if err or type(res) ~= "table" or type(res.data) ~= "table" then
            return cb(nil, err or { msg = "Unexpected response" })
        end
        local ok, value = pcall(pick, res.data)
        if not ok or value == nil or value == vim.NIL then
            return cb(nil, { msg = "Not found" })
        end
        cb(value)
    end
end

---@param title_slug string
---@param cb fun(res?: { title: string, content: string }, err?: lc.err)
function article.editorial(title_slug, cb)
    local query = [[
        query ($slug: String!) {
            ugcArticleOfficialSolutionArticle(questionSlug: $slug) { title content }
        }
    ]]
    utils.query(query, { slug = title_slug }, {
        callback = callback(cb, function(data)
            return data.ugcArticleOfficialSolutionArticle
        end),
    })
end

---@param uuid string
---@param cb fun(res?: { code: string, langSlug: string }[], err?: lc.err)
function article.playground(uuid, cb)
    local query = [[
        query ($uuid: String!) {
            allPlaygroundCodes(uuid: $uuid) { code langSlug }
        }
    ]]
    utils.query(query, { uuid = uuid }, {
        callback = callback(cb, function(data)
            return data.allPlaygroundCodes
        end),
    })
end

---@class lc.article.Summary
---@field title string
---@field topicId integer
---@field author { userName: string }
---@field reactions { count: integer, reactionType: string }[]
---@field hitCount integer

---@param title_slug string
---@param cb fun(res?: lc.article.Summary[], err?: lc.err)
function article.solutions(title_slug, cb)
    local query = [[
        query ($slug: String!, $skip: Int!, $first: Int!) {
            ugcArticleSolutionArticles(questionSlug: $slug, orderBy: HOT, skip: $skip, first: $first) {
                edges { node { title topicId hitCount author { userName } reactions { count reactionType } } }
            }
        }
    ]]
    utils.query(query, { slug = title_slug, skip = 0, first = 20 }, {
        callback = callback(cb, function(data)
            return vim.tbl_map(function(edge)
                return edge.node
            end, data.ugcArticleSolutionArticles.edges)
        end),
    })
end

---@param topic_id integer
---@param cb fun(res?: { title: string, content: string, author: { userName: string } }, err?: lc.err)
function article.solution(topic_id, cb)
    local query = [[
        query ($id: ID!) {
            ugcArticleSolutionArticle(topicId: $id) { title content author { userName } }
        }
    ]]
    utils.query(query, { id = tostring(topic_id) }, {
        callback = callback(cb, function(data)
            return data.ugcArticleSolutionArticle
        end),
    })
end

---@class lc.article.Submission
---@field id string
---@field statusDisplay string
---@field lang string
---@field runtime string
---@field memory string
---@field timestamp string

---@param title_slug string
---@param cb fun(res?: lc.article.Submission[], err?: lc.err)
function article.submissions(title_slug, cb)
    local query = [[
        query ($slug: String!) {
            questionSubmissionList(questionSlug: $slug, offset: 0, limit: 40) {
                submissions { id statusDisplay lang runtime memory timestamp }
            }
        }
    ]]
    utils.query(query, { slug = title_slug }, {
        callback = callback(cb, function(data)
            return data.questionSubmissionList.submissions
        end),
    })
end

---@param id string
---@param cb fun(res?: { code: string }, err?: lc.err)
function article.submission_code(id, cb)
    local query = [[
        query ($id: Int!) {
            submissionDetails(submissionId: $id) { code }
        }
    ]]
    utils.query(query, { id = tonumber(id) }, {
        callback = callback(cb, function(data)
            return data.submissionDetails
        end),
    })
end

return article
