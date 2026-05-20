local replay_task = {};
local help = [];
replay_task.Update <- function ()
{
	::menu.help.Set(help);

	if (::replay.IsFinished())
	{
		::sound.StopBGM(500);
		::loop.EndWithFade();
	}
	// after takeover, b1 will be needed as player input but not pause command
	// so we can't use b1 to trigger pause menu anymore
	else if (::input_all.b10 == 1)
	{
		::sound.PlaySE(111);
		::menu.pause.Initialize(3);
	}
};
this.AddTask(replay_task);
function Pause()
{
}

function BeginResult()
{
	this.End();
}

