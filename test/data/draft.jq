# The thread RECORD of a draft, from the input of `draft` and its id $id
{
  id: $id, source: "https://review.example.org", role: "discussion",
  kind: "thread", basis: $id, links: [["change", "1234"]],
  data: {
    anchor: {on: "change"}, revision: "2", resolved: null,
    comments: [{
      id: $id,
      author: {name: "Me", email: null, username: "me", me: true},
      revision: "2", text: .text, created: "2026-10-23T10:00:00Z",
      reply_to: .reply_to, draft: true
    }]
  },
  notes: {}
}
