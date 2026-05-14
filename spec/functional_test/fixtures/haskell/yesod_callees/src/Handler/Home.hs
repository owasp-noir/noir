module Handler.Home where

import Foundation
import Yesod

getHomeR :: Handler Html
getHomeR = do
  users <- loadUsers
  defaultLayout $ do
    setTitle "Home"
    toWidget [lucius|
      .ignored { color: red; }
      Ignored.template()
    |]
    renderHome users

getBlogPostR :: Text -> Handler Value
getBlogPostR slug = do
  post <- Blog.Service.fetch slug
  returnJson post

postBlogPostR :: Text -> Handler Value
postBlogPostR slug = do
  payload <- requireCheckJsonBody
  saved <- savePost slug payload
  sendResponseStatus status201 saved

handleFaqR :: Handler Value
handleFaqR = do
  item :: FaqItem
  item <- loadFaq
  case item of
    FaqFound value -> returnJson value
    FaqMissing -> notFound

getHealthR :: Handler Value
getHealthR = do
  stats <- healthService
  returnJson stats

helperOnly :: Handler Value
helperOnly = do
  hiddenCall
  returnJson ()
