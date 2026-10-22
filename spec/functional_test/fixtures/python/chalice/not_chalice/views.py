# A route-shaped decorator in a module that does not import chalice.
from mylib import App

app = App()


@app.route('/phantom')
def phantom():
    return 'no'
