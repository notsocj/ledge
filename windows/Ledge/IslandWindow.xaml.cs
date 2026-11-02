using System.Windows;

namespace Ledge;

public partial class IslandWindow : Window
{
    const double TopGap = 8;

    public IslandWindow()
    {
        InitializeComponent();
        Left = (SystemParameters.PrimaryScreenWidth - Width) / 2;
        Top = TopGap;
    }

    void Quit_Click(object sender, RoutedEventArgs e) => Application.Current.Shutdown();
}
