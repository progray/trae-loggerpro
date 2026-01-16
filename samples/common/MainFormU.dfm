object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'LoggerPro SAMPLE - 脱敏测试'
  ClientHeight = 200
  ClientWidth = 723
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = True
  PixelsPerInch = 120
  TextHeight = 13
  object Button1: TButton
    Left = 8
    Top = 8
    Width = 137
    Height = 57
    Caption = 'DEBUG'
    TabOrder = 0
    OnClick = Button1Click
  end
  object Button2: TButton
    Left = 151
    Top = 8
    Width = 137
    Height = 57
    Caption = 'INFO'
    TabOrder = 1
    OnClick = Button2Click
  end
  object Button3: TButton
    Left = 294
    Top = 8
    Width = 137
    Height = 57
    Caption = 'WARNING'
    TabOrder = 2
    OnClick = Button3Click
  end
  object Button4: TButton
    Left = 437
    Top = 8
    Width = 137
    Height = 57
    Caption = 'ERROR'
    TabOrder = 3
    OnClick = Button4Click
  end
  object Button5: TButton
    Left = 8
    Top = 71
    Width = 280
    Height = 57
    Caption = 'Multithread logging'
    TabOrder = 4
    OnClick = Button5Click
  end
  object Button6: TButton
    Left = 580
    Top = 8
    Width = 137
    Height = 57
    Caption = 'FATAL'
    TabOrder = 5
    OnClick = Button6Click
  end
  object btnTestMasking: TButton
    Left = 304
    Top = 71
    Width = 280
    Height = 57
    Caption = '测试脱敏功能'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clBlue
    Font.Height = -13
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    TabOrder = 6
    OnClick = btnTestMaskingClick
  end
  object Label1: TLabel
    Left = 8
    Top = 136
    Width = 697
    Height = 49
    Caption = '提示：点击"测试脱敏功能"按钮，将输出包含敏感信息（手机号和密码）的日志消息，'#13#10'系统会自动对敏感信息进行脱敏处理。请查看控制台或日志文件验证脱敏效果。'
    Font.Charset = DEFAULT_CHARSET
    Font.Color = clMaroon
    Font.Height = -11
    Font.Name = 'Tahoma'
    Font.Style = [fsBold]
    ParentFont = False
    WordWrap = True
  end
end
